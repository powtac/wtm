cask "wtm" do
  version "0.4.3"
  sha256 "25654c764f1891a24e59e61cdb816cf7077f4beda7fcf1a7fecdbee8e779a1f4"

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
