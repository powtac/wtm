cask "wtm" do
  version "0.4.0"
  sha256 "b0926a8f150bc18f218e311488dba6d6417bd0c198a5d436fa3ba155a969755e"

  url "https://github.com/powtac/wtm/releases/download/v#{version}/WTM-#{version}-arm64.dmg"
  name "What The Model"
  desc "Native inventory for locally stored LLMs"
  homepage "https://powtac.github.io/wtm/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia
  depends_on arch: :arm64

  app "WTM.app"
end
