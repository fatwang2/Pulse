.PHONY: test test-claude test-omarchy test-herdr validate

test: test-claude test-omarchy test-herdr

test-claude:
	claude plugin validate plugins/claude-code
	claude plugin validate .
	claude plugin test plugins/claude-code

test-omarchy:
	$(MAKE) -C omarchy test

test-herdr:
	node --test herdr/tests/*.test.mjs

validate: test
	git diff --check
