# Homebrew cask for the Mac app, from the notarized DMG. Published as Casks/ferry.rb in
# github.com/marijnvandevoorde/homebrew-ferry: `brew install --cask marijnvandevoorde/ferry/ferry`.
cask "ferry" do
  version "0.2.1"
  sha256 "2107fc0525e2d6be4c8e003a42e3915bcf0e3d56d8743539aea4877f567c0bc6"

  url "https://github.com/marijnvandevoorde/ferry/releases/download/v#{version}/Ferry-#{version}.dmg"
  name "Ferry"
  desc "Import photos from a camera over Wi-Fi (Fujifilm, Canon, GoPro and more)"
  homepage "https://ferry.small-victories.co"

  depends_on macos: ">= :sonoma"

  app "Ferry.app"

  zap trash: "~/Library/Containers/io.github.fujiimport.FujiImport"
end
