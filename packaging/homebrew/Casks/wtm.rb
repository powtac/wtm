cask "wtm" do
  version "0.5.0"
  sha256 "1b7b5400fd11de5dfd06806ddfbb567afe6d90722b8282b3b39e9a0fdeb206c1"

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
