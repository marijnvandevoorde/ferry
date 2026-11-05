# Homebrew formula for ferryctl, built from source. For a tap: copy to Formula/ferryctl.rb in
# github.com/marijnvandevoorde/homebrew-ferry, then `brew install marijnvandevoorde/ferry/ferryctl`.
class Ferryctl < Formula
  desc "Import photos from a camera over Wi-Fi (Fujifilm, Canon, GoPro and more)"
  homepage "https://ferry.small-victories.co"
  url "https://github.com/marijnvandevoorde/ferry/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "SHA256_OF_THE_TAG_TARBALL"
  license "MIT"
  head "https://github.com/marijnvandevoorde/ferry.git", branch: "main"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :sonoma

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release", "--product", "ferryctl"
    # FerryKit's translations live in a resource bundle that has to sit next to the binary.
    libexec.install ".build/release/ferryctl", ".build/release/FerryKit_FerryKit.bundle"
    bin.install_symlink libexec/"ferryctl"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ferryctl --version")
    assert_match "usage: ferryctl", shell_output("#{bin}/ferryctl --help")
  end
end
