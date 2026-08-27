cask "wtm" do
  version "0.3.7"
  sha256 "682668ea4b2b6a1c2f1964b48551a5f80d96c75a9a9cd9c4729d0e0df7e8ffd2"

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
