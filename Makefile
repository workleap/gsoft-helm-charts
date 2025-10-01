# Automatically declare all targets starting with "tests/" as phony
ALL_TEST_TARGETS := $(shell grep -E '^tests/[^:]*:' $(MAKEFILE_LIST) | sed 's/:.*$$//' | sort | uniq)

PHONY: $(ALL_TEST_TARGETS)

HELM_PLUGINS = $(shell helm env HELM_PLUGINS)
HELM_UNITTEST_PLUGIN = $(HELM_PLUGINS)/helm-unittest.git
HELM_UNITTEST_PLUGIN_GIT = https://github.com/helm-unittest/helm-unittest.git

# When running in CI, fail the entire make process if any test fails so that the job is reported as failed.
# When running locally, do not fail the entire make process if a test fails so that all tests can be run and the user can see all failures at once.
FAIL_ON_ERRORS ?= ${CI}
EXIT_CODE = $(if $(filter TRUE true 1,$(FAIL_ON_ERRORS)),1,0)

HELM_TEMPLATE = helm template ${HELM_RELEASE_NAME} charts/aspnetcore
DISPLAY_RESULT = echo "✅ PASS: $@ - ${TEST_DISPLAY_NAME}" || (echo "❌ ERROR: $@ FAILED - ${TEST_DISPLAY_NAME}" && exit ${EXIT_CODE})
SHOULD_SUCCEED_AND_THEN = >/dev/null 2>&1 &&
SHOULD_FAIL_WITH_ERROR_AND_THEN = 2>&1 | grep -q -E ${EXPECTED_ERROR_MESSAGE} &&

define SHOULD_CONTAIN
2>&1 | grep -q -E $(1)
endef

INTEGRATION_TEST_CHART := charts/aspnetcore/tests/integration/chart
INTEGRATION_TEST_CHART_LOCK_FILE := $(INTEGRATION_TEST_CHART)Chart.lock

$(INTEGRATION_TEST_CHART_LOCK_FILE):
	@helm dependency update charts/aspnetcore/tests/integration/chart 1>/dev/null 2>&1 || (echo "❌ ERROR: Failed to update dependencies for integration test chart" && exit 1)

$(HELM_UNITTEST_PLUGIN):
	@echo "Installing helm unittest plugin..."
	@helm plugin install $(HELM_UNITTEST_PLUGIN_GIT) >/dev/null
	@echo "✅ helm unittest plugin installed."

tests/helm-unittests: $(HELM_UNITTEST_PLUGIN)
	@helm unittest charts/aspnetcore

# Test autoscaling validation: minReplicas is required when autoscaling is enabled
tests/prechecks/autoscaling-minreplicas-required: export TEST_DISPLAY_NAME="Validation should require minReplicas when autoscaling is enabled"
tests/prechecks/autoscaling-minreplicas-required: export EXPECTED_ERROR_MESSAGE="autoscaling.minReplicas is required"
tests/prechecks/autoscaling-minreplicas-required:
	@${HELM_TEMPLATE} --set autoscaling.enabled=true --set autoscaling.minReplicas=null ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test autoscaling with minReplicas exactly equal to minAvailable
tests/prechecks/autoscaling-minreplicas-equal-minavailable: export TEST_DISPLAY_NAME="Validation should prevent minReplicas equal to minAvailable"
tests/prechecks/autoscaling-minreplicas-equal-minavailable: export EXPECTED_ERROR_MESSAGE="autoscaling.minReplicas cannot be less than podDisruptionBudget.minAvailable"
tests/prechecks/autoscaling-minreplicas-equal-minavailable:
	@${HELM_TEMPLATE} --set autoscaling.enabled=true --set autoscaling.minReplicas=2 --set podDisruptionBudget.minAvailable=2 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test autoscaling with minReplicas less than minAvailable
tests/prechecks/autoscaling-minreplicas-less-than-minavailable: export TEST_DISPLAY_NAME="Validation should prevent minReplicas less than minAvailable"
tests/prechecks/autoscaling-minreplicas-less-than-minavailable: export EXPECTED_ERROR_MESSAGE="autoscaling.minReplicas cannot be less than podDisruptionBudget.minAvailable"
tests/prechecks/autoscaling-minreplicas-less-than-minavailable:
	@${HELM_TEMPLATE} --set autoscaling.enabled=true --set autoscaling.minReplicas=2 --set podDisruptionBudget.minAvailable=3 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test replicaCount with minReplicas exactly equal to minAvailable
tests/prechecks/replicaCount-minreplicas-equal-minavailable: export TEST_DISPLAY_NAME="Validation should prevent replicaCount equal to minAvailable"
tests/prechecks/replicaCount-minreplicas-equal-minavailable: export EXPECTED_ERROR_MESSAGE="replicaCount cannot be less than or equal to podDisruptionBudget.minAvailable"
tests/prechecks/replicaCount-minreplicas-equal-minavailable:
	@${HELM_TEMPLATE} --set autoscaling.enabled=false --set replicaCount=2 --set podDisruptionBudget.minAvailable=2 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}


# Test replicaCount with minReplicas less than minAvailable
tests/prechecks/replicaCount-minreplicas-less-than-minavailable: export TEST_DISPLAY_NAME="Validation should prevent minReplicas less than minAvailable"
tests/prechecks/replicaCount-minreplicas-less-than-minavailable: export EXPECTED_ERROR_MESSAGE="replicaCount cannot be less than or equal to podDisruptionBudget.minAvailable"
tests/prechecks/replicaCount-minreplicas-less-than-minavailable:
	@${HELM_TEMPLATE} --set autoscaling.enabled=false --set replicaCount=2 --set podDisruptionBudget.minAvailable=3 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test valid configuration: autoscaling with proper minReplicas
tests/prechecks/autoscaling-valid: export TEST_DISPLAY_NAME="Valid autoscaling configuration should be accepted"
tests/prechecks/autoscaling-valid:
	@${HELM_TEMPLATE} --set autoscaling.enabled=true --set autoscaling.minReplicas=3 --set podDisruptionBudget.minAvailable=1 ${SHOULD_SUCCEED_AND_THEN} ${DISPLAY_RESULT}

# Test valid configuration: PDB with proper minAvailable
tests/prechecks/pdb-valid: export TEST_DISPLAY_NAME="Valid PDB configuration should be accepted"
tests/prechecks/pdb-valid:
	@${HELM_TEMPLATE} --set replicaCount=3 --set podDisruptionBudget.minAvailable=1 ${SHOULD_SUCCEED_AND_THEN} ${DISPLAY_RESULT}

# Test percentage-based minAvailable (should not trigger deadlock validation for percentages)
tests/prechecks/pdb-percentage-valid: export TEST_DISPLAY_NAME="Percentage-based minAvailable should be accepted"
tests/prechecks/pdb-percentage-valid:
	@${HELM_TEMPLATE} --set replicaCount=2 --set podDisruptionBudget.minAvailable="50%" ${SHOULD_SUCCEED_AND_THEN} ${DISPLAY_RESULT}

# Test autoscaling disabled with valid configuration (should pass without prechecks)
tests/prechecks/autoscaling-disabled-valid: export TEST_DISPLAY_NAME="Autoscaling disabled configuration should be accepted"
tests/prechecks/autoscaling-disabled-valid:
	@${HELM_TEMPLATE} --set autoscaling.enabled=false --set replicaCount=1 ${SHOULD_SUCCEED_AND_THEN} ${DISPLAY_RESULT}

# Test autoscaling disabled with replicaCount set to 1 and PDB MinAvailable set to default (should pass without prechecks)
tests/prechecks/autoscaling-disabled-single-replica-zero-minavailable-valid: export TEST_DISPLAY_NAME="Autoscaling disabled configuration with single replica should be accepted even with default PDB MinAvailable since PDB will not be created"
tests/prechecks/autoscaling-disabled-single-replica-zero-minavailable-valid:
	@${HELM_TEMPLATE} --set autoscaling.enabled=false --set replicaCount=1 ${SHOULD_SUCCEED_AND_THEN} ${DISPLAY_RESULT}

# Test autoscaling with minReplicas set to 0 (edge case)
tests/prechecks/autoscaling-minreplicas-zero: export TEST_DISPLAY_NAME="Validation should prevent minReplicas=0 when minAvailable=1"
tests/prechecks/autoscaling-minreplicas-zero: export EXPECTED_ERROR_MESSAGE="(autoscaling.*minimum|Must be greater than or equal to 1)"
tests/prechecks/autoscaling-minreplicas-zero:
	@${HELM_TEMPLATE} --set autoscaling.enabled=true --set autoscaling.minReplicas=0 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test autoscaling with negative minReplicas (edge case)
tests/prechecks/autoscaling-minreplicas-negative: export TEST_DISPLAY_NAME="Validation should prevent negative minReplicas"
tests/prechecks/autoscaling-minreplicas-negative: export EXPECTED_ERROR_MESSAGE="(autoscaling.*minimum|Must be greater than or equal to 1)"
tests/prechecks/autoscaling-minreplicas-negative:
	@${HELM_TEMPLATE} --set autoscaling.enabled=true --set autoscaling.minReplicas=-1 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test autoscaling with large values (boundary testing)
tests/prechecks/autoscaling-large-values: export TEST_DISPLAY_NAME="Large valid values should be accepted"
tests/prechecks/autoscaling-large-values:
	@${HELM_TEMPLATE} --set autoscaling.enabled=true --set autoscaling.minReplicas=100 --set podDisruptionBudget.minAvailable=50 ${SHOULD_SUCCEED_AND_THEN} ${DISPLAY_RESULT}

# Test percentage-based minAvailable with autoscaling (should work)
tests/prechecks/autoscaling-with-percentage-pdb: export TEST_DISPLAY_NAME="Autoscaling with percentage-based PDB should be valid"
tests/prechecks/autoscaling-with-percentage-pdb:
	@${HELM_TEMPLATE} --set autoscaling.enabled=true --set autoscaling.minReplicas=3 --set podDisruptionBudget.minAvailable="25%" ${SHOULD_SUCCEED_AND_THEN} $(DISPLAY_RESULT)

# Schema validation tests
# Test replicaCount minimum validation (should fail with replicaCount=0)
tests/schema/replicacount-zero: export TEST_DISPLAY_NAME="Schema should reject replicaCount=0"
tests/schema/replicacount-zero: export EXPECTED_ERROR_MESSAGE="(replicaCount.*minimum|Must be greater than or equal to 1)"
tests/schema/replicacount-zero:
	@${HELM_TEMPLATE} --set replicaCount=0 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test replicaCount negative validation (should fail with replicaCount=-1)
tests/schema/replicacount-negative: export TEST_DISPLAY_NAME="Schema should reject negative replicaCount"
tests/schema/replicacount-negative: export EXPECTED_ERROR_MESSAGE="(replicaCount.*minimum|Must be greater than or equal to 1)"
tests/schema/replicacount-negative:
	@${HELM_TEMPLATE} --set replicaCount=-1 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test terminationGracePeriodSeconds negative validation (should fail)
tests/schema/termination-grace-period-negative: export TEST_DISPLAY_NAME="Schema should reject negative terminationGracePeriodSeconds"
tests/schema/termination-grace-period-negative: export EXPECTED_ERROR_MESSAGE="(terminationGracePeriodSeconds.*minimum|Must be greater than or equal to 0)"
tests/schema/termination-grace-period-negative:
	@${HELM_TEMPLATE} --set terminationGracePeriodSeconds=-1 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test environment enum validation (should fail with invalid environment)
tests/schema/environment-invalid: export TEST_DISPLAY_NAME="Schema should reject invalid environment values"
tests/schema/environment-invalid: export EXPECTED_ERROR_MESSAGE="(environment.*|Must be one of the following)"
tests/schema/environment-invalid:
	@${HELM_TEMPLATE} --set environment="Invalid" ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test environment valid values (should pass)
tests/schema/environment-valid: export TEST_DISPLAY_NAME="Valid environment should be accepted"
tests/schema/environment-valid:
	@${HELM_TEMPLATE} --set environment="Production" ${SHOULD_SUCCEED_AND_THEN} ${DISPLAY_RESULT}

# Test image.pullPolicy enum validation (should fail with invalid pullPolicy)
tests/schema/image-pullpolicy-invalid: export TEST_DISPLAY_NAME="Schema should reject invalid pullPolicy values"
tests/schema/image-pullpolicy-invalid: export EXPECTED_ERROR_MESSAGE="(pullPolicy.*|Must be one of)"
tests/schema/image-pullpolicy-invalid:
	@${HELM_TEMPLATE} --set image.pullPolicy="InvalidPolicy" ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test service.port minimum validation (should fail with port=0)
tests/schema/service-port-zero: export TEST_DISPLAY_NAME="Schema should reject port=0"
tests/schema/service-port-zero: export EXPECTED_ERROR_MESSAGE="(port.*minimum|Must be greater than or equal to 1)"
tests/schema/service-port-zero:
	@${HELM_TEMPLATE} --set service.port=0 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test service.port maximum validation (should fail with port=65536)
tests/schema/service-port-in-range: export TEST_DISPLAY_NAME="Schema should accept port in valid range"
tests/schema/service-port-in-range:
	@${HELM_TEMPLATE} --set service.port=8080 ${SHOULD_SUCCEED_AND_THEN} ${DISPLAY_RESULT}

# Test service.port maximum validation (should fail with port=65536)
tests/schema/service-port-too-high: export TEST_DISPLAY_NAME="Schema should reject port greater than 65535"
tests/schema/service-port-too-high: export EXPECTED_ERROR_MESSAGE="(port.*maximum|Must be less than or equal to 65535)"
tests/schema/service-port-too-high:
	@${HELM_TEMPLATE} --set service.port=65536 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test ingress.pathType enum validation (should fail with invalid pathType)
tests/schema/ingress-pathtype-invalid: export TEST_DISPLAY_NAME="Schema should reject invalid pathType values"
tests/schema/ingress-pathtype-invalid: export EXPECTED_ERROR_MESSAGE="(pathType.*|Must be one of)"
tests/schema/ingress-pathtype-invalid:
	@${HELM_TEMPLATE} --set ingress.pathType="InvalidType" ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test ingress.hostname format validation (should fail with invalid hostname)
tests/schema/ingress-hostname-invalid: export TEST_DISPLAY_NAME="Schema should reject invalid hostname format"
tests/schema/ingress-hostname-invalid: export EXPECTED_ERROR_MESSAGE="(ingress.*hostname.*not valid hostname)"
tests/schema/ingress-hostname-invalid:
	@${HELM_TEMPLATE} --set ingress.hostname="invalid..hostname" ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test podDisruptionBudget.minAvailable with zero integer (should fail due to minimum: 1)
tests/schema/pdb-minavailable-zero: export TEST_DISPLAY_NAME="Schema should reject minAvailable=0"
tests/schema/pdb-minavailable-zero: export EXPECTED_ERROR_MESSAGE="(minAvailable.*minimum|Must be greater than or equal to 1)"
tests/schema/pdb-minavailable-zero:
	@${HELM_TEMPLATE} --set podDisruptionBudget.minAvailable=0 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test autoscaling.maxReplicas minimum validation (should fail with maxReplicas=0)
tests/schema/autoscaling-maxreplicas-zero: export TEST_DISPLAY_NAME="Schema should reject maxReplicas=0"
tests/schema/autoscaling-maxreplicas-zero: export EXPECTED_ERROR_MESSAGE="(maxReplicas.*minimum|Must be greater than or equal to 1)"
tests/schema/autoscaling-maxreplicas-zero:
	@${HELM_TEMPLATE} --set autoscaling.maxReplicas=0 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test autoscaling.targetCPUUtilizationPercentage minimum validation (should fail with 0%)
tests/schema/autoscaling-cpu-target-zero: export TEST_DISPLAY_NAME="Schema should reject targetCPU=0"
tests/schema/autoscaling-cpu-target-zero: export EXPECTED_ERROR_MESSAGE="(targetCPUUtilizationPercentage.*minimum|Must be greater than or equal to 1)"
tests/schema/autoscaling-cpu-target-zero:
	@${HELM_TEMPLATE} --set autoscaling.targetCPUUtilizationPercentage=0 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test autoscaling.targetCPUUtilizationPercentage maximum validation (should fail with 101%)
tests/schema/autoscaling-cpu-target-too-high: export TEST_DISPLAY_NAME="Schema should reject targetCPU greater than 100"
tests/schema/autoscaling-cpu-target-too-high: export EXPECTED_ERROR_MESSAGE="(targetCPUUtilizationPercentage.*maximum|Must be less than or equal to 100)"
tests/schema/autoscaling-cpu-target-too-high:
	@${HELM_TEMPLATE} --set autoscaling.targetCPUUtilizationPercentage=101 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test extraEnvVars missing required name field (should fail)
tests/schema/extraenvvars-missing-name: export TEST_DISPLAY_NAME="Schema should require name field in extraEnvVars"
tests/schema/extraenvvars-missing-name: export EXPECTED_ERROR_MESSAGE="(extraEnvVars.*missing property.*name)"
tests/schema/extraenvvars-missing-name:
	@${HELM_TEMPLATE} --set-json 'extraEnvVars=[{"value":"test"}]' ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test valid extraEnvVars (should pass)
tests/schema/extraenvvars-valid: export TEST_DISPLAY_NAME="Valid extraEnvVars should be accepted"
tests/schema/extraenvvars-valid:
	@${HELM_TEMPLATE} --set-json 'extraEnvVars=[{"name":"TEST_VAR","value":"test"}]' ${SHOULD_SUCCEED_AND_THEN} ${DISPLAY_RESULT}

# Test functionality: Chart can be used as a sub-chart
tests/integration/usable-as-sub-chart: export TEST_DISPLAY_NAME="Chart can be used as a sub-chart"
tests/integration/usable-as-sub-chart: $(INTEGRATION_TEST_CHART) $(INTEGRATION_TEST_CHART_LOCK_FILE)
	@helm template $< ${SHOULD_SUCCEED_AND_THEN} ${DISPLAY_RESULT}

# Run all tests
test: tests
tests: $(ALL_TEST_TARGETS)
