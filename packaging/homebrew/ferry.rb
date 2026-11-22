# Homebrew cask for the Mac app, from the notarized DMG. Published as Casks/ferry.rb in
# github.com/marijnvandevoorde/homebrew-ferry: `brew install --cask marijnvandevoorde/ferry/ferry`.
cask "ferry" do
  version "0.3.2"
  sha256 "a05a052ff6f41dfe10e3930267cb9c43bdf6cc1d21b8da61871b97aa1d2a9661"

  url "https://github.com/marijnvandevoorde/ferry/releases/download/v#{version}/Ferry-#{version}.dmg"
  name "Ferry"
  desc "Import photos from a camera over Wi-Fi (Fujifilm, Canon, GoPro and more)"
  homepage "https://ferry.small-victories.co"

  depends_on macos: ">= :sonoma"

  app "Ferry.app"

  zap trash: "~/Library/Containers/io.github.fujiimport.FujiImport"
end
