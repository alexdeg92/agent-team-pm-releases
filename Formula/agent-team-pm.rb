class AgentTeamPm < Formula
  desc "Project-manager skill for teams of coding agents in herdr"
  homepage "https://github.com/alexdeg92/agent-team-pm-releases"
  url "https://registry.npmjs.org/agent-team-pm/-/agent-team-pm-0.1.2.tgz"
  sha256 "6d84955609b7f8a4e7e562b681efa46e78e2fcc932dd01f195a22954488c046c"

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
