class MacosCalendarMcp < Formula
  desc "MCP server for macOS Calendar — gives AI agents access to EventKit"
  homepage "https://github.com/miguelarios/macos-calendar-mcp"
  url "https://github.com/miguelarios/macos-calendar-mcp/archive/refs/tags/v0.5.0.tar.gz"
  sha256 "20af59d3ef26c9ed41feeb42b8d5151e74c23136fef7bbbbf1a4cd726cd8d857"
  version "0.5.0"
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

    # Write wrapper script with startup delay to avoid cold-boot race
    (libexec/"calendar-mcp-server").write <<~BASH
      #!/bin/bash
      # Wrapper script for Calendar MCP Server
      # Includes a short startup delay to avoid race conditions with clients
      # that launch at login (e.g., Claude Desktop).

      echo "[$(date '+%Y-%m-%d %H:%M:%S')] calendar-mcp-server starting..." >&2

      # Brief delay on cold boot so the server is ready before fast-launching clients
      sleep 3

      PYTHON="#{libexec}/venv/bin/python3"
      SERVER="#{libexec}/calendar_mcp_server.py"

      if [ ! -x "$PYTHON" ]; then
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Python not found at $PYTHON" >&2
          exit 1
      fi

      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Launching server: $PYTHON $SERVER" >&2
      exec "$PYTHON" "$SERVER" "$@"
    BASH
    chmod 0755, libexec/"calendar-mcp-server"

    # Install CLI with start/stop/restart/logs commands
    (bin/"macos-calendar-mcp").write <<~BASH
      #!/bin/bash
      # macos-calendar-mcp — CLI for the Calendar MCP Server

      LABEL="homebrew.mxcl.macos-calendar-mcp"
      PORT="9876"
      LOG_DIR="#{var}/log/macos-calendar-mcp"

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

      cmd_restart() {
          echo "Restarting Calendar MCP Server..."
          brew services restart macos-calendar-mcp
          echo "Done. Waiting for server..."
          sleep 4
          cmd_status
      }

      cmd_start() {
          echo "Starting Calendar MCP Server..."
          brew services start macos-calendar-mcp
          echo "Done. Waiting for server..."
          sleep 4
          cmd_status
      }

      cmd_stop() {
          echo "Stopping Calendar MCP Server..."
          brew services stop macos-calendar-mcp
          echo "Done."
      }

      cmd_logs() {
          echo "=== stderr (last 20 lines) ==="
          tail -20 "$LOG_DIR/stderr.log" 2>/dev/null || echo "(no stderr log)"
          echo ""
          echo "=== stdout (last 20 lines) ==="
          tail -20 "$LOG_DIR/stdout.log" 2>/dev/null || echo "(no stdout log)"
      }

      case "${1:-status}" in
          status) cmd_status ;;
          restart) cmd_restart ;;
          start) cmd_start ;;
          stop) cmd_stop ;;
          logs) cmd_logs ;;
          *) echo "Usage: macos-calendar-mcp [status|start|stop|restart|logs]"; exit 1 ;;
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
      View logs:    macos-calendar-mcp logs
    EOS
  end

  test do
    assert_match "calendars", shell_output("#{bin}/cal-tools 2>&1", 1)
  end
end
