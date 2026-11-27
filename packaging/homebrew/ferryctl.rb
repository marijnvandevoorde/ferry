# Homebrew formula for ferryctl, built from source. Published as Formula/ferryctl.rb in
# github.com/marijnvandevoorde/homebrew-ferry: `brew install marijnvandevoorde/ferry/ferryctl`.
class Ferryctl < Formula
  desc "Import photos from a camera over Wi-Fi (Fujifilm, Canon, GoPro and more)"
  homepage "https://ferry.small-victories.co"
  url "https://github.com/marijnvandevoorde/ferry/archive/refs/tags/v0.3.4.tar.gz"
  sha256 "986b5a70e37491668b6cb402c68b1dac871a6f2ecd871c6ebe42ed0838fb665f"
  license "MIT"
  head "https://github.com/marijnvandevoorde/ferry.git", branch: "main"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :sonoma

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release", "--product", "ferryctl"
    bin.install ".build/release/ferryctl"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ferryctl --version")
    assert_match "usage: ferryctl", shell_output("#{bin}/ferryctl --help")
  end
end
