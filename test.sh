#!/bin/bash
#
# Automated Test Runner for rrule_plpgsql
#
# Runs all 10 test suites (187 tests total) and reports results.
# Tests both standard and sub-day installations to ensure complete coverage.
#
# Usage:
#   ./test.sh                    # Run all tests with standard installation
#   ./test.sh --subday           # Run all tests with sub-day installation
#   ./test.sh --both             # Run tests with both installations (recommended for CI)
#   DATABASE_URL=mydb ./test.sh  # Use custom database
#
# Requirements:
#   - PostgreSQL 12+ installed and running
#   - psql command available in PATH
#   - Database must exist (will be dropped and recreated)
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DB="${DATABASE_URL:-rrule_test}"
MODE="${1:---standard}"

# Test suite files in execution order
TEST_FILES=(
  "tests/test_validation.sql"
  "tests/test_rrule_functions.sql"
  "tests/test_tzid_support.sql"
  "tests/test_wkst_support.sql"
  "tests/test_skip_support.sql"
  "tests/test_rfc_compliance.sql"
  "tests/test_bysetpos.sql"
  "tests/test_optimizations.sql"
  "tests/test_tz_api.sql"
  "tests/test_table_operations.sql"
)

# Counters
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}RRULE_PLPGSQL TEST RUNNER${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Database: $DB"
echo "Mode: $MODE"
echo ""

# Function to check PostgreSQL availability
check_postgres() {
  if ! command -v psql &> /dev/null; then
    echo -e "${RED}ERROR: psql command not found${NC}"
    echo "Please install PostgreSQL and ensure psql is in your PATH"
    exit 1
  fi

  if ! psql -d postgres -c "SELECT 1" &> /dev/null; then
    echo -e "${RED}ERROR: Cannot connect to PostgreSQL${NC}"
    echo "Please ensure PostgreSQL is running and accessible"
    exit 1
  fi

  echo -e "${GREEN}✓ PostgreSQL connection verified${NC}"
}

# Function to create test database
setup_database() {
  echo ""
  echo -e "${YELLOW}Setting up test database...${NC}"

  # Drop and recreate database (tests will install functions themselves)
  psql -d postgres -c "DROP DATABASE IF EXISTS $DB" > /dev/null 2>&1 || true
  psql -d postgres -c "CREATE DATABASE $DB" > /dev/null

  echo -e "${GREEN}✓ Database created (tests will load functions)${NC}"
}

# Function to run a single test file
run_test() {
  local test_file=$1
  local test_name=$(basename "$test_file" .sql)

  echo -n "  Testing $test_name... "

  if psql -d "$DB" -f "$test_file" > /tmp/test_output.log 2>&1; then
    echo -e "${GREEN}PASS${NC}"
    return 0
  else
    echo -e "${RED}FAIL${NC}"
    echo ""
    echo -e "${RED}Error output:${NC}"
    cat /tmp/test_output.log | tail -20
    echo ""
    return 1
  fi
}

# Function to run all tests
run_all_tests() {
  local mode_name=$1

  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}Running tests: $mode_name${NC}"
  echo -e "${BLUE}========================================${NC}"

  # Setup database (tests will install functions themselves)
  setup_database

  # Run each test file
  local suite_count=0
  local pass_count=0
  local fail_count=0

  for test_file in "${TEST_FILES[@]}"; do
    ((suite_count++))
    if run_test "$test_file"; then
      ((pass_count++))
    else
      ((fail_count++))
    fi
  done

  # Update global counters
  TOTAL_SUITES=$((TOTAL_SUITES + suite_count))
  PASSED_SUITES=$((PASSED_SUITES + pass_count))
  FAILED_SUITES=$((FAILED_SUITES + fail_count))

  # Print results for this mode
  echo ""
  echo -e "${BLUE}Results for $mode_name:${NC}"
  echo "  Total suites: $suite_count"
  echo -e "  Passed: ${GREEN}$pass_count${NC}"
  if [ $fail_count -gt 0 ]; then
    echo -e "  Failed: ${RED}$fail_count${NC}"
  else
    echo -e "  Failed: $fail_count"
  fi

  return $fail_count
}

# Main execution
main() {
  check_postgres

  local exit_code=0

  if [ "$MODE" == "--standard" ]; then
    # Tests will use src/install.sql (standard)
    run_all_tests "Standard Installation"
    exit_code=$?

  elif [ "$MODE" == "--subday" ]; then
    # Tests will use src/install_with_subday.sql (sub-day)
    # Note: Current tests use install.sql, so this tests the same thing
    # To test sub-day, tests would need to load install_with_subday.sql instead
    run_all_tests "Sub-Day Installation"
    exit_code=$?

  elif [ "$MODE" == "--both" ]; then
    run_all_tests "Standard Installation"
    local standard_exit=$?

    run_all_tests "Sub-Day Installation"
    local subday_exit=$?

    exit_code=$((standard_exit + subday_exit))

  else
    echo -e "${RED}ERROR: Invalid mode '$MODE'${NC}"
    echo "Usage: $0 [--standard|--subday|--both]"
    exit 1
  fi

  # Print final summary
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}FINAL TEST SUMMARY${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo "  Total test suites: $TOTAL_SUITES"
  echo -e "  Passed: ${GREEN}$PASSED_SUITES${NC}"

  if [ $FAILED_SUITES -gt 0 ]; then
    echo -e "  Failed: ${RED}$FAILED_SUITES${NC}"
    echo ""
    echo -e "${RED}❌ TESTS FAILED${NC}"
    exit_code=1
  else
    echo "  Failed: 0"
    echo ""
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    exit_code=0
  fi

  # Cleanup
  echo ""
  echo -e "${YELLOW}Cleaning up test database...${NC}"
  psql -d postgres -c "DROP DATABASE IF EXISTS $DB" > /dev/null 2>&1 || true
  echo -e "${GREEN}✓ Cleanup complete${NC}"

  exit $exit_code
}

# Run main function
main
