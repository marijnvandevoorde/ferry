# Homebrew cask for the Mac app, from the notarized DMG. Published as Casks/ferry.rb in
# github.com/marijnvandevoorde/homebrew-ferry: `brew install --cask marijnvandevoorde/ferry/ferry`.
cask "ferry" do
  version "0.3.1"
  sha256 "0600870e3df377489e58a42411fa41dad081c9ba2e3ef483497efa7346cf6f0c"

  url "https://github.com/marijnvandevoorde/ferry/releases/download/v#{version}/Ferry-#{version}.dmg"
  name "Ferry"
  desc "Import photos from a camera over Wi-Fi (Fujifilm, Canon, GoPro and more)"
  homepage "https://ferry.small-victories.co"

  depends_on macos: ">= :sonoma"

  app "Ferry.app"

  zap trash: "~/Library/Containers/io.github.fujiimport.FujiImport"
end
