/*
Copyright 2025.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Package controller implements the controller logic
package controller

import (
	"context"
	"fmt"

	hypershiftv1beta1 "github.com/openshift/hypershift/api/hypershift/v1beta1"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	controllerutil "sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	ctrllog "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	"github.com/innabox/cloudkit-operator/api/v1alpha1"
)

// NewComponentFn is the type of a function that creates a required component
type NewComponentFn func(context.Context, *v1alpha1.ClusterOrder) (*appResource, error)

type appResource struct {
	object   client.Object
	mutateFn controllerutil.MutateFn
}

type component struct {
	name string
	fn   NewComponentFn
}

func (r *ClusterOrderReconciler) components() []component {
	return []component{
		{"Namespace", r.newNamespace},
		{"ServiceAccount", r.newServiceAccount},
		{"RoleBinding", r.newAdminRoleBinding},
	}
}

// ClusterOrderReconciler reconciles a ClusterOrder object
type ClusterOrderReconciler struct {
	client.Client
	Scheme                *runtime.Scheme
	CreateClusterWebhook  string
	DeleteClusterWebhook  string
	ClusterOrderNamespace string
}

func NewClusterOrderReconciler(client client.Client, scheme *runtime.Scheme, createClusterWebhook string, deleteClusterWebhook string, clusterOrderNamespace string) *ClusterOrderReconciler {
	if clusterOrderNamespace == "" {
		clusterOrderNamespace = defaultClusterOrderNamespace
	}
	return &ClusterOrderReconciler{
		Client:                client,
		Scheme:                scheme,
		CreateClusterWebhook:  createClusterWebhook,
		DeleteClusterWebhook:  deleteClusterWebhook,
		ClusterOrderNamespace: clusterOrderNamespace,
	}
}

// +kubebuilder:rbac:groups=cloudkit.openshift.io,resources=clusterorders,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=cloudkit.openshift.io,resources=clusterorders/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=cloudkit.openshift.io,resources=clusterorders/finalizers,verbs=update
// +kubebuilder:rbac:groups="",resources=namespaces;serviceaccounts,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=rbac.authorization.k8s.io,resources=rolebindings,verbs=get;list;watch;create;update;patch;delete

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
func (r *ClusterOrderReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := ctrllog.FromContext(ctx)

	instance := &v1alpha1.ClusterOrder{}
	err := r.Client.Get(ctx, req.NamespacedName, instance)
	if err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	// FIXME: This is probably the wrong solution.
	if instance.GetNamespace() != r.ClusterOrderNamespace {
		return ctrl.Result{}, nil
	}

	log.Info(fmt.Sprintf("Start reconcile for %s", instance.GetName()))

	var res ctrl.Result
	if instance.ObjectMeta.DeletionTimestamp.IsZero() {
		res, err = r.handleUpdate(ctx, req, instance)
	} else {
		res, err = r.handleDelete(ctx, req, instance)
	}

	log.Info(fmt.Sprintf("End reconcile for %s", instance.GetName()))
	return res, err
}

// SetupWithManager sets up the controller with the Manager.
func (r *ClusterOrderReconciler) SetupWithManager(mgr ctrl.Manager) error {
	labelPredicate, err := predicate.LabelSelectorPredicate(metav1.LabelSelector{
		MatchExpressions: []metav1.LabelSelectorRequirement{
			{
				Key:      cloudkitClusterOrderNameLabel,
				Operator: metav1.LabelSelectorOpExists,
			},
		},
	})
	if err != nil {
		return err
	}

	return ctrl.NewControllerManagedBy(mgr).
		For(&v1alpha1.ClusterOrder{}).
		Watches(
			&corev1.Namespace{},
			handler.EnqueueRequestsFromMapFunc(r.mapObjectToCluster),
			builder.WithPredicates(labelPredicate),
		).
		Watches(
			&corev1.ServiceAccount{},
			handler.EnqueueRequestsFromMapFunc(r.mapObjectToCluster),
			builder.WithPredicates(labelPredicate),
		).
		Watches(
			&rbacv1.RoleBinding{},
			handler.EnqueueRequestsFromMapFunc(r.mapObjectToCluster),
			builder.WithPredicates(labelPredicate),
		).
		Watches(
			&hypershiftv1beta1.HostedCluster{},
			handler.EnqueueRequestsFromMapFunc(r.mapObjectToCluster),
			builder.WithPredicates(labelPredicate),
		).
		Complete(r)
}

// mapObjectToCluster maps an event for a watched object to the associated
// ClusterOrder resource.
func (r *ClusterOrderReconciler) mapObjectToCluster(ctx context.Context, obj client.Object) []reconcile.Request {
	log := ctrllog.FromContext(ctx)

	clusterOrderName, exists := obj.GetLabels()[cloudkitClusterOrderNameLabel]
	if !exists {
		return nil
	}

	clusterOrderNamespace, exists := obj.GetLabels()[cloudkitClusterOrderNamespaceLabel]
	if !exists {
		return nil
	}

	log.Info("Selecting " + obj.GetName())

	return []reconcile.Request{
		{
			NamespacedName: client.ObjectKey{
				Name:      clusterOrderName,
				Namespace: clusterOrderNamespace,
			},
		},
	}
}

//nolint:unparam
func (r *ClusterOrderReconciler) handleUpdate(ctx context.Context, _ ctrl.Request, instance *v1alpha1.ClusterOrder) (ctrl.Result, error) {
	log := ctrllog.FromContext(ctx)

	if controllerutil.AddFinalizer(instance, cloudkitFinalizer) {
		if err := r.Update(ctx, instance); err != nil {
			return ctrl.Result{}, err
		}
	}

	for _, component := range r.components() {
		log.Info("Handling component " + component.name)

		resource, err := component.fn(ctx, instance)
		if err != nil {
			log.Error(err, fmt.Sprintf("Failed to mutate resource %s", component.name))
			return ctrl.Result{}, err
		}

		result, err := controllerutil.CreateOrUpdate(ctx, r.Client, resource.object, resource.mutateFn)
		if err != nil {
			log.Error(err, "Failed to create or update "+component.name)
			return ctrl.Result{}, err
		}
		switch result {
		case controllerutil.OperationResultCreated:
			log.Info(fmt.Sprintf("Created %s for %s", component.name, instance.GetName()))
		case controllerutil.OperationResultUpdated:
			log.Info(fmt.Sprintf("Updated %s for %s", component.name, instance.GetName()))
		}
	}

	if url := r.CreateClusterWebhook; url != "" {
		if err := triggerWebHook(ctx, url, instance); err != nil {
			log.Error(err, "Failed to trigger webhook")
			return ctrl.Result{}, err
		}
	}

	return ctrl.Result{}, nil
}

func (r *ClusterOrderReconciler) waitHostedClusterDelete(ctx context.Context, instance *v1alpha1.ClusterOrder) (bool, error) {
	log := ctrllog.FromContext(ctx)

	var hostedClusterList hypershiftv1beta1.HostedClusterList
	if err := r.List(ctx, &hostedClusterList, labelSelectorFromInstance(instance)); err != nil {
		log.Error(err, "failed to list hosted clusters")
		return false, err
	}

	if len(hostedClusterList.Items) > 0 {
		if url := r.DeleteClusterWebhook; url != "" {
			if err := triggerWebHook(ctx, url, instance); err != nil {
				log.Error(err, "Failed to trigger webhook")
				return false, err
			}
		}

		return false, nil
	}

	return true, nil
}

func (r *ClusterOrderReconciler) waitNamespaceDelete(ctx context.Context, instance *v1alpha1.ClusterOrder) (bool, error) {
	log := ctrllog.FromContext(ctx)

	var namespaceList corev1.NamespaceList
	if err := r.List(ctx, &namespaceList, labelSelectorFromInstance(instance)); err != nil {
		log.Error(err, "Failed to list namespaces")
		return false, err
	}

	if len(namespaceList.Items) > 0 {
		for _, ns := range namespaceList.Items {
			log.Info(fmt.Sprintf("Delete ns %s for %s", ns.GetName(), instance.GetName()))
			if err := r.Client.Delete(ctx, &ns); err != nil {
				log.Error(err, "Failed to delete namespace "+ns.GetName())
				return false, err
			}
		}
		return false, nil
	}

	return true, nil
}

//nolint:unparam
func (r *ClusterOrderReconciler) handleDelete(ctx context.Context, _ ctrl.Request, instance *v1alpha1.ClusterOrder) (ctrl.Result, error) {
	log := ctrllog.FromContext(ctx)
	log.Info("Delete " + instance.GetName())

	if !controllerutil.ContainsFinalizer(instance, cloudkitFinalizer) {
		return ctrl.Result{}, nil
	}

	// Wait until HostedCluster has been deleted
	if gone, err := r.waitHostedClusterDelete(ctx, instance); !gone {
		return ctrl.Result{}, err
	}

	// Wait until Namespace has been deleted
	if gone, err := r.waitNamespaceDelete(ctx, instance); !gone {
		return ctrl.Result{}, err
	}

	if controllerutil.RemoveFinalizer(instance, cloudkitFinalizer) {
		if err := r.Update(ctx, instance); err != nil {
			return ctrl.Result{}, err
		}
	}

	return ctrl.Result{}, nil
}

func labelSelectorFromInstance(instance *v1alpha1.ClusterOrder) client.MatchingLabels {
	return client.MatchingLabels{
		cloudkitClusterOrderNamespaceLabel: instance.GetNamespace(),
		cloudkitClusterOrderNameLabel:      instance.GetName(),
	}
}
