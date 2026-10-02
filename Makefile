.PHONY: test test-claude test-omarchy validate

test: test-claude test-omarchy

test-claude:
	claude plugin validate plugins/claude-code
	claude plugin validate .
	claude plugin test plugins/claude-code

test-omarchy:
	$(MAKE) -C omarchy test

validate: test
	git diff --check
