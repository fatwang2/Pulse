.PHONY: test test-claude test-omarchy test-herdr test-opencode test-raycast test-metrix validate

test: test-claude test-omarchy test-herdr test-opencode test-raycast test-metrix

test-claude:
	claude plugin validate plugins/claude-code
	claude plugin validate .
	claude plugin test plugins/claude-code

test-omarchy:
	$(MAKE) -C omarchy test

test-herdr:
	node --test herdr/tests/*.test.mjs

test-opencode:
	node --test opencode/tests/*.test.mjs

test-metrix:
	node --test metrix/tests/*.test.mjs

test-raycast:
	cd raycast && npm ci && npx --yes tsx@4.23.15 --test ../tests/raycast/*.test.ts && npm run lint && npm run build && npm run typecheck

validate: test
	git diff --check
