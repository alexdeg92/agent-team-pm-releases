class AgentTeamPm < Formula
  desc "Project-manager skill for teams of coding agents in herdr"
  homepage "https://github.com/alexdeg92/agent-team-pm-releases"
  url "https://github.com/alexdeg92/agent-team-pm-releases/releases/download/v0.1.0/agent-team-pm-0.1.0.tgz"
  sha256 "c2b3c6dc9f6720d42dce2e495d995b152562b8f05537a21755ab80d5e9a80eaf"

  license "MIT"

  depends_on "jq"
  depends_on "node"
  depends_on "python@3.14"

  def install
    libexec.install Dir["*"]
    (bin/"agent-team-pm").write_env_script libexec/"bin/agent-team-pm.js", PATH: "#{formula_opt_bin("node")}:$PATH"
  end

  def caveats
    <<~EOS
      Run `agent-team-pm install` to install the skill in your home directory.
      Install herdr separately and authenticate your coding-agent CLIs.
      The installer links team into ~/.local/bin; add that directory to PATH.
    EOS
  end

  test do
    ENV["HOME"] = testpath
    system bin/"agent-team-pm", "install"
    assert_path_exists testpath/".claude/skills/agent-team-pm/SKILL.md"
    system bin/"agent-team-pm", "uninstall"
    refute_path_exists testpath/".claude/skills/agent-team-pm"
  end
end
