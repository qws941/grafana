#!/bin/bash

# Grafana API Utility Script
# Load credentials from .env.credentials

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDS_FILE="$SCRIPT_DIR/../.env.credentials"

if [[ ! -f "$CREDS_FILE" ]]; then
    echo "Error: Credentials file not found at $CREDS_FILE"
    exit 1
fi

# Load credentials
source "$CREDS_FILE"

# Function to make API calls with token
grafana_api() {
    local endpoint="$1"
    local method="${2:-GET}"
    local data="$3"

    local url="${GRAFANA_LOCAL_URL}${endpoint}"

    if [[ -n "$data" ]]; then
        curl -s -X "$method" \
            -H "Authorization: Bearer $GRAFANA_SERVICE_ACCOUNT_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$url"
    else
        curl -s -X "$method" \
            -H "Authorization: Bearer $GRAFANA_SERVICE_ACCOUNT_TOKEN" \
            "$url"
    fi
}

# Function to make admin API calls with basic auth
grafana_admin() {
    local endpoint="$1"
    local method="${2:-GET}"
    local data="$3"

    local url="${GRAFANA_LOCAL_URL}${endpoint}"

    if [[ -n "$data" ]]; then
        curl -s -X "$method" \
            -H "Content-Type: application/json" \
            -u "$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD" \
            -d "$data" \
            "$url"
    else
        curl -s -X "$method" \
            -u "$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD" \
            "$url"
    fi
}

# Usage examples
show_usage() {
    echo "Usage: $0 [command] [args...]"
    echo ""
    echo "Commands:"
    echo "  user           - Get current user info"
    echo "  stats          - Get admin stats"
    echo "  datasources    - List all datasources"
    echo "  dashboards     - List all dashboards"
    echo "  api [endpoint] - Make custom API call"
    echo "  help           - Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 user"
    echo "  $0 api /api/health"
    echo "  $0 datasources"
}

# Main command handling
case "${1:-help}" in
    "user")
        echo "Current user info:"
        grafana_api "/api/user" | jq .
        ;;
    "stats")
        echo "Admin stats:"
        grafana_admin "/api/admin/stats" | jq .
        ;;
    "datasources")
        echo "Datasources:"
        grafana_api "/api/datasources" | jq .
        ;;
    "dashboards")
        echo "Dashboards:"
        grafana_api "/api/search" | jq .
        ;;
    "api")
        if [[ -z "$2" ]]; then
            echo "Error: API endpoint required"
            echo "Usage: $0 api [endpoint]"
            exit 1
        fi
        grafana_api "$2"
        ;;
    "help"|*)
        show_usage
        ;;
esac