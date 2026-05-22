cask "thunder" do
  version "1.7.0"
  sha256 "3e2b05d36baf5fe6a1befbc225e8f86fd151258c00ba16feea8ba3c914c20d61"

  # Tratamento dinâmico: o tag é v1.7.0, mas o DMG de release segue a versão do Xcode (1.7) com build (1).
  url "https://github.com/carlosxfelipe/thunder/releases/download/v#{version}/Thunder-#{version.major_minor}-1.dmg"
  name "Thunder"
  desc "File manager written in Swift with SwiftUI"
  homepage "https://github.com/carlosxfelipe/thunder"

  app "Thunder.app"

  zap trash: [
    "~/Library/Application Support/Thunder",
    "~/Library/Caches/com.example.thunder",
    "~/Library/Preferences/com.example.thunder.plist",
    "~/Library/Saved Application State/com.example.thunder.savedState",
  ]
end
