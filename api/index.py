import sys
import os
from pathlib import Path

# Add web_server directory to sys.path so we can import app and other modules
web_server_dir = Path(__file__).parent.parent / "web_server"
if str(web_server_dir.absolute()) not in sys.path:
    sys.path.insert(0, str(web_server_dir.absolute()))

from app import app
