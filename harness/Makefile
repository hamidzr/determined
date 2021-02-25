PROJECT_ROOT := ..

.PHONY: clean
clean:
	rm -rf .pytest_cache/
	rm -rf .mypy_cache/
	rm -rf *.egg-info/
	rm -rf pip-wheel-metadata/
	rm -rf dist/
	rm -rf build/
	rm -rf determined/api_bindings/swagger_client
	find . \( -name __pycache__ -o -name \*.pyc \) -delete

.PHONY: build
build: get-deps-api
	python setup.py -q bdist_wheel

.PHONY: build-bindings
build-bindings:
	$(MAKE) -C ${PROJECT_ROOT}/bindings build
.PHONY: get-deps-api
get-deps-api:
	# WARN this has a dependency on build-bindings which isn't link through make here
	rm -rf determined/api-bindings/swagger_client
	cp -r ${PROJECT_ROOT}/bindings/build/python/swagger_client determined/api_bindings/swagger_client

.PHONY: publish
publish:
	twine upload --verbose --non-interactive dist/*

.PHONY: fmt
fmt:
	isort -y
	black .

.PHONY: check
check:
	isort --check-only
	black . --check
	flake8
	mypy .

.PHONY: test
test:
	pytest -v --runslow --durations=0 tests

.PHONY: test-tf2
test-tf2:
	pip freeze | grep "tensorflow==2.*"
	pytest -v --runslow --durations=0 tests/experiment/tensorflow
	# We must run these tests separately becuase estimators need to disable v2
	# behavior (a global operation). We are explicitly testing eager execution
	# for tf keras which needs v2 behavior enabled. You can't enable v2 behavior
	# anywhere but the "start" of your program. See:
	# https://github.com/tensorflow/tensorflow/issues/18304#issuecomment-379435515.
	pytest -v --runslow --durations=0 tests/experiment/keras
