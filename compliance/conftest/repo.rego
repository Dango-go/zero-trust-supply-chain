package main

# Policy-as-Code rules for repository baseline configuration (security/repo-baseline.json).
# Usage: conftest test security/repo-baseline.json -p compliance/conftest/repo.rego

# 1. Enforce admin compliance on main branch
deny[msg] {
    bp := input.branch_protection.main
    not bp.enforce_admins == true
    msg := "Branch 'main' must set enforce_admins: true."
}

# 2. Disallow force pushes on main branch
deny[msg] {
    bp := input.branch_protection.main
    not bp.allow_force_pushes == false
    msg := "Branch 'main' must set allow_force_pushes: false."
}

# 3. Disallow branch deletions on main branch
deny[msg] {
    bp := input.branch_protection.main
    not bp.allow_deletions == false
    msg := "Branch 'main' must set allow_deletions: false."
}

# 4. Enforce linear commit history on main branch
deny[msg] {
    bp := input.branch_protection.main
    not bp.required_linear_history == true
    msg := "Branch 'main' must set required_linear_history: true."
}

# 5. Require PR reviews, stale review dismissal, and CODEOWNERS approval
deny[msg] {
    reviews := input.branch_protection.main.required_pull_request_reviews
    not reviews.dismiss_stale_reviews == true
    msg := "Branch 'main' must set required_pull_request_reviews.dismiss_stale_reviews: true."
}

deny[msg] {
    reviews := input.branch_protection.main.required_pull_request_reviews
    not reviews.require_code_owner_reviews == true
    msg := "Branch 'main' must set required_pull_request_reviews.require_code_owner_reviews: true."
}

deny[msg] {
    reviews := input.branch_protection.main.required_pull_request_reviews
    reviews.required_approving_review_count < 1
    msg := "Branch 'main' must require at least 1 approving PR review."
}

# 6. Require strict status checks with non-empty contexts
deny[msg] {
    checks := input.branch_protection.main.required_status_checks
    not checks.strict == true
    msg := "Branch 'main' must set required_status_checks.strict: true."
}

deny[msg] {
    checks := input.branch_protection.main.required_status_checks
    count(checks.contexts) == 0
    msg := "Branch 'main' must define at least one required status check context."
}

# 7. Protect release tags (v*) against mutation or deletion
deny[msg] {
    tag_rule := input.tag_protection["v*"]
    not tag_rule.immutable == true
    msg := "Tag protection for 'v*' must set immutable: true."
}

# 8. Require human reviewer approval on the 'release' GitHub Environment
deny[msg] {
    env := input.environments.release
    not env.required_reviewers == true
    msg := "GitHub Environment 'release' must set required_reviewers: true."
}
