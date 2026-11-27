# Read-only App Store Connect check immediately before internal-only export.
require "base64"
require "json"
require "net/http"
require "openssl"
require "uri"

def encode(bytes)
  Base64.urlsafe_encode64(bytes, padding: false)
end

def apple_token
  header = { alg: "ES256", kid: ENV.fetch("ASC_KEY_ID"), typ: "JWT" }
  now = Time.now.to_i
  claims = { iss: ENV.fetch("ASC_ISSUER_ID"), iat: now, exp: now + 300, aud: "appstoreconnect-v1" }
  payload = [header, claims].map { |part| encode(JSON.generate(part)) }.join(".")
  key = OpenSSL::PKey.read(ENV.fetch("ASC_PRIVATE_KEY"))
  der = key.sign("SHA256", payload)
  raw = OpenSSL::ASN1.decode(der).value.map { |integer| integer.value.to_s(2).rjust(32, "\0") }.join
  "#{payload}.#{encode(raw)}"
end

def apple_list(path, token)
  uri = URI("https://api.appstoreconnect.apple.com/v1/#{path}")
  records = []
  loop do
    raise "Unexpected App Store Connect pagination URL" unless uri.scheme == "https" &&
      uri.host == "api.appstoreconnect.apple.com" && uri.port == 443 && uri.path.start_with?("/v1/")
    request = Net::HTTP::Get.new(uri, { "Authorization" => "Bearer #{token}" })
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    raise "App Store Connect audience check failed (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
    page = JSON.parse(response.body)
    records.concat(page.fetch("data"))
    following = page.fetch("links")["next"]
    return records if following.nil?
    uri = URI(following)
  end
end

def check_audience(email, list)
  raise "Set OWNER_TESTFLIGHT_EMAIL in the signing environment" if email.strip.empty?
  apps = list.call("apps?filter%5BbundleId%5D=org.cirrusretro.player")
  raise "Expected one Cirrus Retro app" unless apps.size == 1
  groups = list.call("apps/#{apps.first.fetch('id')}/betaGroups")
  found_owner = false
  groups.each do |group|
    attributes = group.fetch("attributes")
    internal = attributes.fetch("isInternalGroup")
    next if internal == false # The exporter requires internal-only delivery.
    raise "Unknown tester group type" unless internal == true
    owner = attributes.fetch("name") == "Owner"
    automatic = attributes.fetch("hasAccessToAllBuilds")
    raise "Unknown automatic distribution setting" unless [true, false].include?(automatic)
    next unless owner || automatic
    testers = list.call("betaGroups/#{group.fetch('id')}/betaTesters")
    unless testers.all? { |t| t.fetch("attributes").fetch("email").casecmp?(email) }
      raise "A receiving group contains another tester"
    end
    if owner
      raise "Expected exactly one tester in Owner" unless testers.size == 1
      found_owner = true
    end
  end
  raise "Missing internal Owner group" unless found_owner
end

if $PROGRAM_NAME == __FILE__
  token = apple_token
  check_audience(ENV.fetch("OWNER_TESTFLIGHT_EMAIL"), ->(path) { apple_list(path, token) })
  puts "Verified the owner-only TestFlight audience"
end
