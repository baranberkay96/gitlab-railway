# Run with `gitlab-rails runner` by railway-runner-bootstrap.sh.
#
# Creates a short-lived personal access token for root whose value is
# GITLAB_RUNNER_BOOTSTRAP_TOKEN, scoped to `create_runner` only (it can create
# runners and nothing else). The GitLab Runner service uses it once, then
# revokes it. An existing token with the same value (active, expired or
# revoked) is left untouched, so a revoked token is never re-created.
#
# Setting a known token value follows GitLab's documented "create a personal
# access token programmatically" procedure.

token_value = ENV['GITLAB_RUNNER_BOOTSTRAP_TOKEN'].to_s.strip
if token_value.length < 20
  puts '[railway-runner-bootstrap] GITLAB_RUNNER_BOOTSTRAP_TOKEN shorter than 20 characters; skipping'
  exit 0
end

existing = PersonalAccessToken.find_by_token(token_value)
if existing
  state = if existing.revoked? then 'revoked'
          elsif existing.expired? then 'expired'
          else 'active'
          end
  puts "[railway-runner-bootstrap] token already exists (#{state}); nothing to do"
  exit 0
end

user = User.find_by_username('root') || User.admins.order(:id).first
raise 'no administrator account found' unless user

attributes = {
  name: 'Railway runner bootstrap (create_runner only)',
  scopes: [:create_runner],
  expires_at: 30.days.from_now.to_date
}
if PersonalAccessToken.column_names.include?('organization_id') && defined?(Organizations::Organization)
  organization = Organizations::Organization.find_by(id: user.try(:organization_id)) ||
                 Organizations::Organization.order(:id).first
  attributes[:organization] = organization if organization
end

pat = user.personal_access_tokens.build(attributes)
pat.set_token(token_value)
pat.save!
puts "[railway-runner-bootstrap] created token ##{pat.id} for #{user.username}, expires #{pat.expires_at}"
