#!/bin/sh
set -e

# Simple test script
echo "Test script starting..."
echo "Environment variables:"
env | grep DB_SERVICE_NAME || echo "DB_SERVICE_NAME not set"
echo "Script execution complete"
