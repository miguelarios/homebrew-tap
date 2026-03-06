class MacosCalendarMcp < Formula
  desc "MCP server for macOS Calendar — gives AI agents access to EventKit"
  homepage "https://github.com/miguelarios/macos-calendar-mcp"
  head "https://github.com/miguelarios/macos-calendar-mcp.git", branch: "main"

  depends_on "python@3"
  depends_on :macos

  def install
    # Compile Swift binary
    bin.mkpath
    system "swiftc", "cal-tools.swift", "-o", bin/"cal-tools"

    # Install Python server
    libexec.install "calendar_mcp_server.py"

    # Create venv and install fastmcp
    venv = libexec/"venv"
    system Formula["python@3"].opt_bin/"python3", "-m", "venv", venv.to_s
    system venv/"bin/pip", "install", "--quiet", "fastmcp"

    # Write wrapper script with Homebrew paths
    (libexec/"calendar-mcp-server").write <<~BASH
      #!/bin/bash
      exec "#{libexec}/venv/bin/python3" "#{libexec}/calendar_mcp_server.py" "$@"
    BASH
    chmod 0755, libexec/"calendar-mcp-server"

    # Install status CLI with Homebrew paths baked in
    (bin/"macos-calendar-mcp").write <<~BASH
      #!/bin/bash
      # macos-calendar-mcp — CLI for the Calendar MCP Server

      LABEL="homebrew.mxcl.macos-calendar-mcp"
      PORT="9876"

      cmd_status() {
          local url="http://127.0.0.1:${PORT}/mcp"

          echo "Calendar MCP Server (Homebrew)"
          echo "  Port: $PORT"
          echo "  URL:  $url"
          echo ""

          if brew services list 2>/dev/null | grep -q "macos-calendar-mcp.*started"; then
              echo "  Status: running"
          else
              echo "  Status: not running"
              echo "  Start with: brew services start macos-calendar-mcp"
          fi
      }

      case "${1:-status}" in
          status) cmd_status ;;
          *) echo "Usage: macos-calendar-mcp [status]"; exit 1 ;;
      esac
    BASH
    chmod 0755, bin/"macos-calendar-mcp"
  end

  service do
    run [opt_libexec/"calendar-mcp-server"]
    keep_alive crashed: true
    environment_variables CAL_TOOLS_PATH: opt_bin/"cal-tools",
                          CALENDAR_MCP_PORT: "9876"
    log_path var/"log/macos-calendar-mcp/stdout.log"
    error_log_path var/"log/macos-calendar-mcp/stderr.log"
    working_dir opt_libexec
  end

  def caveats
    <<~EOS
      To start the MCP server:
        brew services start macos-calendar-mcp

      Then add to your MCP client config:
        Claude Code: {"mcpServers": {"calendar": {"type": "streamable-http", "url": "http://localhost:9876/mcp"}}}
        Goose: extensions.calendar = {type: "streamable_http", uri: "http://localhost:9876/mcp"}

      On first use, macOS will prompt for calendar access permission.
      Check status: macos-calendar-mcp status
    EOS
  end

  test do
    assert_match "calendars", shell_output("#{bin}/cal-tools 2>&1", 1)
  end
end
