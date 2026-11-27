require "minitest/autorun"
require_relative "../scripts/check-testflight-audience"

class TestFlightAudienceTest < Minitest::Test
  def setup
    @email = "owner@example.test"
    @other = { "attributes" => { "email" => "other@example.test" } }
    @groups = ["Owner", "Default"].map do |name|
      { "id" => name, "attributes" => { "name" => name, "isInternalGroup" => true,
                                        "hasAccessToAllBuilds" => name == "Default" } }
    end
    @responses = {
      "apps?filter%5BbundleId%5D=org.cirrusretro.player" => [{ "id" => "id" }],
      "apps/id/betaGroups" => @groups,
      "betaGroups/Owner/betaTesters" => [{ "attributes" => { "email" => @email } }],
      "betaGroups/Default/betaTesters" => []
    }
  end

  def check
    check_audience(@email, @responses.method(:fetch))
  end

  def test_only_owner_receives_the_build
    check
    @responses["betaGroups/Default/betaTesters"] << @other
    assert_raises(RuntimeError) { check }
    @groups.last["attributes"]["hasAccessToAllBuilds"] = false
    check
    @responses["betaGroups/Owner/betaTesters"] << @other
    assert_raises(RuntimeError) { check }
  end

  def test_missing_owner_or_unknown_distribution_is_rejected
    @groups.last["attributes"].delete("hasAccessToAllBuilds")
    assert_raises(KeyError) { check }
    @groups.clear
    assert_raises(RuntimeError) { check }
  end
end
