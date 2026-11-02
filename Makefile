.PHONY: test test-claude test-omarchy test-herdr test-raycast validate

test: test-claude test-omarchy test-herdr test-raycast

test-claude:
	claude plugin validate plugins/claude-code
	claude plugin validate .
	claude plugin test plugins/claude-code

test-omarchy:
	$(MAKE) -C omarchy test

test-herdr:
	node --test herdr/tests/*.test.mjs

test-raycast:
	cd raycast && npm ci && npm test && npm run lint && npm run build

validate: test
	git diff --check
