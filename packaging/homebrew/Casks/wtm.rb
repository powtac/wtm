cask "wtm" do
  version "0.4.2"
  sha256 "c79619ca1ed5199181fe7861b3ea9a681837fa9a7ecd738b63c51d63df757c3f"

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
