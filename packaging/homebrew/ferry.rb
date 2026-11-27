# Homebrew cask for the Mac app, from the notarized DMG. Published as Casks/ferry.rb in
# github.com/marijnvandevoorde/homebrew-ferry: `brew install --cask marijnvandevoorde/ferry/ferry`.
cask "ferry" do
  version "0.3.4"
  sha256 "7c5eb438192088ef72a7f46c8f13c4d83ae798ddd904fe3da1abfee3059be571"

  url "https://github.com/marijnvandevoorde/ferry/releases/download/v#{version}/Ferry-#{version}.dmg"
  name "Ferry"
  desc "Import photos from a camera over Wi-Fi (Fujifilm, Canon, GoPro and more)"
  homepage "https://ferry.small-victories.co"

  depends_on macos: ">= :sonoma"

  app "Ferry.app"

  zap trash: "~/Library/Containers/io.github.fujiimport.FujiImport"
end
