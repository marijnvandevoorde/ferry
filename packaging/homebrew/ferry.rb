# Homebrew cask for the Mac app, from the notarized DMG. Published as Casks/ferry.rb in
# github.com/marijnvandevoorde/homebrew-ferry: `brew install --cask marijnvandevoorde/ferry/ferry`.
cask "ferry" do
  version "0.2.2"
  sha256 "7be52c581d4ab7ccebb2f792ba85998da27e8dd0707d5b97e3efa78b8f7a1513"

  url "https://github.com/marijnvandevoorde/ferry/releases/download/v#{version}/Ferry-#{version}.dmg"
  name "Ferry"
  desc "Import photos from a camera over Wi-Fi (Fujifilm, Canon, GoPro and more)"
  homepage "https://ferry.small-victories.co"

  depends_on macos: ">= :sonoma"

  app "Ferry.app"

  zap trash: "~/Library/Containers/io.github.fujiimport.FujiImport"
end
