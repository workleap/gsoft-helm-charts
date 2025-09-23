# Automatically declare all targets starting with "tests/" as phony
ALL_TEST_TARGETS := $(shell grep -E '^tests/[^:]*:' $(MAKEFILE_LIST) | sed 's/:.*$$//' | sort | uniq)

PHONY: $(ALL_TEST_TARGETS)

HELM_TEMPLATE = helm template ${HELM_RELEASE_NAME} charts/aspnetcore
DISPLAY_RESULT = echo "✅ PASS: $@ - ${TEST_DISPLAY_NAME}" || echo "❌ ERROR: $@ FAILED - ${TEST_DISPLAY_NAME}"
DISPLAY_RESULT_INVERTED = echo "❌ ERROR: $@ FAILED - ${TEST_DISPLAY_NAME}" || echo "✅ PASS: $@ - ${TEST_DISPLAY_NAME}"
SHOULD_SUCCEED_AND_THEN = >/dev/null 2>&1 &&
SHOULD_FAIL_WITH_ERROR_AND_THEN = 2>&1 | grep -q -E ${EXPECTED_ERROR_MESSAGE} &&

define SHOULD_CONTAIN
2>&1 | grep -q -E $(1)
endef

# Test autoscaling validation: minReplicas is required when autoscaling is enabled
tests/prechecks/autoscaling-minreplicas-required: export TEST_DISPLAY_NAME="Validation should require minReplicas when autoscaling is enabled"
tests/prechecks/autoscaling-minreplicas-required: export EXPECTED_ERROR_MESSAGE="autoscaling.minReplicas is required"
tests/prechecks/autoscaling-minreplicas-required:
	@${HELM_TEMPLATE} --set autoscaling.enabled=true --set autoscaling.minReplicas=null ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test autoscaling with minReplicas exactly equal to minAvailable (edge case - should fail)
tests/prechecks/autoscaling-minreplicas-equal-minavailable: export TEST_DISPLAY_NAME="Validation should prevent minReplicas == minAvailable"
tests/prechecks/autoscaling-minreplicas-equal-minavailable: export EXPECTED_ERROR_MESSAGE="autoscaling.minReplicas cannot be less than podDisruptionBudget.minAvailable"
tests/prechecks/autoscaling-minreplicas-equal-minavailable:
	@${HELM_TEMPLATE} --set autoscaling.enabled=true --set autoscaling.minReplicas=2 --set podDisruptionBudget.minAvailable=2 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

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

# Test autoscaling with minReplicas set to 0 (edge case)
tests/prechecks/autoscaling-minreplicas-zero: export TEST_DISPLAY_NAME="Validation should prevent minReplicas=0 when minAvailable=1"
tests/prechecks/autoscaling-minreplicas-zero: export EXPECTED_ERROR_MESSAGE="autoscaling.minReplicas: Must be greater than or equal to 1"
tests/prechecks/autoscaling-minreplicas-zero:
	@${HELM_TEMPLATE} --set autoscaling.enabled=true --set autoscaling.minReplicas=0 ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test autoscaling with negative minReplicas (edge case)
tests/prechecks/autoscaling-minreplicas-negative: export TEST_DISPLAY_NAME="Validation should prevent negative minReplicas"
tests/prechecks/autoscaling-minreplicas-negative: export EXPECTED_ERROR_MESSAGE="autoscaling.minReplicas: Must be greater than or equal to 1"
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
tests/schema/service-port-in-range: export TEST_DISPLAY_NAME="Schema should reject port greater than 65535"
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
tests/schema/ingress-hostname-invalid: export EXPECTED_ERROR_MESSAGE="(hostname.*format|Invalid hostname)"
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
tests/schema/extraenvvars-missing-name: export EXPECTED_ERROR_MESSAGE="(name.*required|Missing required property)"
tests/schema/extraenvvars-missing-name:
	@${HELM_TEMPLATE} --set-json 'extraEnvVars=[{"value":"test"}]' ${SHOULD_FAIL_WITH_ERROR_AND_THEN} ${DISPLAY_RESULT}

# Test valid extraEnvVars (should pass)
tests/schema/extraenvvars-valid: export TEST_DISPLAY_NAME="Valid extraEnvVars should be accepted"
tests/schema/extraenvvars-valid:
	@${HELM_TEMPLATE} --set-json 'extraEnvVars=[{"name":"TEST_VAR","value":"test"}]' ${SHOULD_SUCCEED_AND_THEN} ${DISPLAY_RESULT}

# Tests for _helpers.tpl template functions
# Test aspnetcore.selectorLabels helper with default values
tests/helpers/selector-labels-default: export TEST_DISPLAY_NAME="selectorLabels helper should generate correct labels with defaults"
tests/helpers/selector-labels-default:
	@${HELM_TEMPLATE} $(call SHOULD_CONTAIN,"app.kubernetes.io/name: aspnetcore") && \
    ${HELM_TEMPLATE} $(call SHOULD_CONTAIN,"app.kubernetes.io/instance: release-name") && ${DISPLAY_RESULT}

# Test aspnetcore.selectorLabels helper with custom release name
tests/helpers/selector-labels-custom-release: export TEST_DISPLAY_NAME="selectorLabels helper should use custom release name"
tests/helpers/selector-labels-custom-release: export HELM_RELEASE_NAME=my-custom-release
tests/helpers/selector-labels-custom-release:
	@${HELM_TEMPLATE} $(call SHOULD_CONTAIN,"app.kubernetes.io/name: aspnetcore") && \
    ${HELM_TEMPLATE} $(call SHOULD_CONTAIN,"app.kubernetes.io/instance: my-custom-release") && ${DISPLAY_RESULT}

# Test aspnetcore.standardLabels helper includes selector labels
tests/helpers/standard-labels-includes-selector: export TEST_DISPLAY_NAME="standardLabels helper should include selector labels"
tests/helpers/standard-labels-includes-selector:
	@${HELM_TEMPLATE} $(call SHOULD_CONTAIN,"app.kubernetes.io/name: aspnetcore") && \
    ${HELM_TEMPLATE} $(call SHOULD_CONTAIN,"app.kubernetes.io/instance: release-name") && \
    ${DISPLAY_RESULT}

# Test aspnetcore.standardLabels helper includes helm chart label
tests/helpers/standard-labels-chart: export TEST_DISPLAY_NAME="standardLabels helper should include helm chart label"
tests/helpers/standard-labels-chart:
	@${HELM_TEMPLATE} $(call SHOULD_CONTAIN,"helm.sh/chart: aspnetcore-") && ${DISPLAY_RESULT}

# Test aspnetcore.standardLabels helper includes version from image.tag
tests/helpers/standard-labels-version: export TEST_DISPLAY_NAME="standardLabels helper should include version from image.tag"
tests/helpers/standard-labels-version:
	@${HELM_TEMPLATE} --set image.tag="v1.2.3" $(call SHOULD_CONTAIN,'app.kubernetes.io/version: "v1.2.3"') && ${DISPLAY_RESULT}

# Test aspnetcore.standardLabels helper includes managed-by label
tests/helpers/standard-labels-managed-by: export TEST_DISPLAY_NAME="standardLabels helper should include managed-by label"
tests/helpers/standard-labels-managed-by:
	@${HELM_TEMPLATE} $(call SHOULD_CONTAIN,"app.kubernetes.io/managed-by: Helm") && ${DISPLAY_RESULT}

# Test aspnetcore.standardLabels helper chart label format is correct
tests/helpers/standard-labels-chart-format: export TEST_DISPLAY_NAME="standardLabels helper should format chart label correctly"
tests/helpers/standard-labels-chart-format:
	@${HELM_TEMPLATE} $(call SHOULD_CONTAIN,"helm.sh/chart: aspnetcore-[0-9]") && ${DISPLAY_RESULT}

# Test aspnetcore.serviceAccountName with serviceAccount.create=true and default name
tests/helpers/service-account-name-create-default: export TEST_DISPLAY_NAME="serviceAccountName helper should generate default name when create=true"
tests/helpers/service-account-name-create-default:
	@${HELM_TEMPLATE} --set serviceAccount.create=true $(call SHOULD_CONTAIN,"serviceAccountName: release-name-serviceaccount") && ${DISPLAY_RESULT}

# Test aspnetcore.serviceAccountName with serviceAccount.create=true and custom name
tests/helpers/service-account-name-create-custom: export TEST_DISPLAY_NAME="serviceAccountName helper should use custom name when provided"
tests/helpers/service-account-name-create-custom:
	@${HELM_TEMPLATE} --set serviceAccount.create=true --set serviceAccount.name="my-custom-sa" $(call SHOULD_CONTAIN,"serviceAccountName: my-custom-sa") && ${DISPLAY_RESULT}

# Test aspnetcore.serviceAccountName with serviceAccount.create=false and default
tests/helpers/service-account-name-no-create-default: export TEST_DISPLAY_NAME="serviceAccountName helper should use 'default' when create=false and no name"
tests/helpers/service-account-name-no-create-default:
	@${HELM_TEMPLATE} --set serviceAccount.create=false $(call SHOULD_CONTAIN,"serviceAccountName: default") && ${DISPLAY_RESULT}

# Test aspnetcore.serviceAccountName with serviceAccount.create=false and custom name
tests/helpers/service-account-name-no-create-custom: export TEST_DISPLAY_NAME="serviceAccountName helper should use custom name when create=false but name provided"
tests/helpers/service-account-name-no-create-custom:
	@${HELM_TEMPLATE} --set serviceAccount.create=false --set serviceAccount.name="existing-sa" $(call SHOULD_CONTAIN,"serviceAccountName: existing-sa") && ${DISPLAY_RESULT}

# Test aspnetcore.serviceAccountName with different release names
tests/helpers/service-account-name-custom-release: export TEST_DISPLAY_NAME="serviceAccountName helper should use custom release name in generated name"
tests/helpers/service-account-name-custom-release:
	@helm template my-app charts/aspnetcore --set serviceAccount.create=true $(call SHOULD_CONTAIN,"serviceAccountName: my-app-serviceaccount") && ${DISPLAY_RESULT}

# Test edge case: very long release name gets properly truncated in chart label
tests/helpers/standard-labels-long-name-truncation: export TEST_DISPLAY_NAME="standardLabels helper should handle long names and truncate properly"
tests/helpers/standard-labels-long-name-truncation:
	@helm template very-very-very-very-very-very-very-long-release-name charts/aspnetcore | \
    grep -E "helm.sh/chart: aspnetcore-[0-9]" | \
    awk -F': ' '{if (length($$2) <= 63) exit 0; else exit 1}' && ${DISPLAY_RESULT}

# Test that selectorLabels are used in both deployment and service
tests/helpers/selector-labels-consistency: export TEST_DISPLAY_NAME="selectorLabels should be used consistently in deployment and service"
tests/helpers/selector-labels-consistency:
	@${HELM_TEMPLATE} $(call SHOULD_CONTAIN,"app.kubernetes.io/name: aspnetcore") && \
    ${HELM_TEMPLATE} $(call SHOULD_CONTAIN,"app.kubernetes.io/instance: release-name") && \
    [ $$(${HELM_TEMPLATE} | grep -c "app.kubernetes.io/name: aspnetcore") -ge 2 ] && \
    [ $$(${HELM_TEMPLATE} | grep -c "app.kubernetes.io/instance: release-name") -ge 2 ] && ${DISPLAY_RESULT}

# Run all tests
test: tests
tests: $(ALL_TEST_TARGETS)

