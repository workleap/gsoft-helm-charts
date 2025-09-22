# Automatically declare all targets starting with "tests/" as phony
TESTS_TARGETS := $(filter tests/%,$(MAKECMDGOALS))
.PHONY: $(TESTS_TARGETS)

# # Test that PDB is not created when replicaCount=1 (default test)
tests/pdb/default:
	@helm template charts/aspnetcore --set replicaCount=1 | \
    grep -q -i "poddisruptionbudget" && echo "ERROR: $@ FAILED - PDB should not be created when replicaCount=1" || echo "PASS: $@ - No PDB found when replicaCount=1 (as expected)"

# Test that PDB is created when replicaCount>1
tests/pdb/created-when-replicas-gt-1:
	@helm template charts/aspnetcore --set replicaCount=2 | \
    grep -q -i "poddisruptionbudget" && echo "PASS: $@ - PDB created when replicaCount=2" || echo "ERROR: $@ FAILED - PDB should be created when replicaCount>1"

# Test autoscaling validation: minReplicas is required when autoscaling is enabled
tests/prechecks/autoscaling-minreplicas-required:
	@helm template charts/aspnetcore --set autoscaling.enabled=true --set autoscaling.minReplicas=null 2>&1 | \
    grep -q "autoscaling.minReplicas is required" && echo "PASS: $@ - Validation correctly requires minReplicas" || echo "ERROR: $@ FAILED - Should require minReplicas when autoscaling is enabled"

# Test autoscaling validation: minReplicas must be greater than PDB minAvailable
tests/prechecks/autoscaling-minreplicas-vs-pdb:
	@helm template charts/aspnetcore --set autoscaling.enabled=true --set autoscaling.minReplicas=1 --set podDisruptionBudget.minAvailable=1 2>&1 | \
    grep -q "autoscaling.minReplicas cannot be less than podDisruptionBudget.minAvailable" && echo "PASS: $@ - Validation correctly prevents minReplicas <= minAvailable" || echo "ERROR: $@ FAILED - Should prevent minReplicas <= minAvailable"

# Test PDB deadlock validation: minAvailable cannot be >= replicaCount
tests/prechecks/pdb-deadlock-equal:
	@helm template charts/aspnetcore --set autoscaling.enabled=false --set replicaCount=2 --set podDisruptionBudget.minAvailable=2 2>&1 | \
    grep -q "Pod Disruption Budget minAvailable cannot be greater than or equal to replicaCount" && echo "PASS: $@ - Validation correctly prevents deadlock (minAvailable=replicaCount)" || echo "ERROR: $@ FAILED - Should prevent minAvailable >= replicaCount"

# Test PDB deadlock validation: minAvailable cannot be > replicaCount
tests/prechecks/pdb-deadlock-greater:
	@helm template charts/aspnetcore --set autoscaling.enabled=false --set replicaCount=2 --set podDisruptionBudget.minAvailable=3 2>&1 | \
    grep -q "Pod Disruption Budget minAvailable cannot be greater than or equal to replicaCount" && echo "PASS: $@ - Validation correctly prevents deadlock (minAvailable>replicaCount)" || echo "ERROR: $@ FAILED - Should prevent minAvailable >= replicaCount"

# Test PDB deadlock validation is skipped when replicaCount=1
tests/prechecks/pdb-deadlock-skip-when-replicas-1:
	@helm template charts/aspnetcore --set replicaCount=1 --set podDisruptionBudget.minAvailable=2 2>/dev/null | \
    grep -q -i "poddisruptionbudget" && echo "ERROR: $@ FAILED - PDB should not be created when replicaCount=1" || echo "PASS: $@ - PDB validation skipped and no PDB created when replicaCount=1"

# Test valid configuration: autoscaling with proper minReplicas
tests/prechecks/autoscaling-valid:
	@helm template charts/aspnetcore --set autoscaling.enabled=true --set autoscaling.minReplicas=3 --set podDisruptionBudget.minAvailable=1 >/dev/null 2>&1 && \
    echo "PASS: $@ - Valid autoscaling configuration accepted" || echo "ERROR: $@ FAILED - Valid configuration should be accepted"

# Test valid configuration: PDB with proper minAvailable
tests/prechecks/pdb-valid:
	@helm template charts/aspnetcore --set replicaCount=3 --set podDisruptionBudget.minAvailable=1 >/dev/null 2>&1 && \
    echo "PASS: $@ - Valid PDB configuration accepted" || echo "ERROR: $@ FAILED - Valid configuration should be accepted"

# Test percentage-based minAvailable (should not trigger deadlock validation for percentages)
tests/prechecks/pdb-percentage-valid:
	@helm template charts/aspnetcore --set replicaCount=2 --set podDisruptionBudget.minAvailable="50%" >/dev/null 2>&1 && \
    echo "PASS: $@ - Percentage-based minAvailable accepted" || echo "ERROR: $@ FAILED - Percentage-based minAvailable should be accepted"

# Run all PDB tests
tests/pdb/all: tests/pdb/default tests/pdb/created-when-replicas-gt-1

# Run all precheck tests
tests/prechecks/all: tests/prechecks/autoscaling-minreplicas-required tests/prechecks/autoscaling-minreplicas-vs-pdb tests/prechecks/pdb-deadlock-equal tests/prechecks/pdb-deadlock-greater tests/prechecks/pdb-deadlock-skip-when-replicas-1 tests/prechecks/autoscaling-valid tests/prechecks/pdb-valid tests/prechecks/pdb-percentage-valid

# Run all tests
tests/all: tests/pdb/all tests/prechecks/all

