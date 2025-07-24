#!/bin/bash
set -e

# Update system
yum update -y

# Install required packages
yum install -y python3 python3-pip git unzip wget

# Create app directory
mkdir -p /opt/app
cd /opt/app

# Create app user
useradd -r -s /bin/false appuser
chown appuser:appuser /opt/app

# Create requirements.txt
cat > requirements.txt << 'EOF'
backports-abc==0.5
certifi==2017.4.17
chardet==3.0.4
click==6.7
Faker==0.7.17
Flask==0.12.2
Flask-SQLAlchemy==2.2
gevent==1.2.2
greenlet==0.4.12
grequests==0.3.0
idna==2.5
ipaddress==1.0.18
itsdangerous==0.24
Jinja2==2.9.6
lxml==4.2.1
MarkupSafe==1.0
PyJWT==1.5.2
python-dateutil==2.6.0
python-docx==0.8.5
PyYAML==5.4.1
requests==2.18.1
singledispatch==3.4.0.3
six==1.10.0
SQLAlchemy==1.1.11
tornado==4.5.1
urllib3==1.21.1
Werkzeug==0.14.1
EOF

# Create app.py (simplified version for hosting)
cat > app.py << 'EOF'
from flask import session, Flask, jsonify, request, Response, render_template, render_template_string, url_for
from flask_sqlalchemy import SQLAlchemy
import jwt
from jwt.exceptions import DecodeError, MissingRequiredClaimError, InvalidKeyError
import json
import hashlib
import datetime
import os
from faker import Faker
import random
from werkzeug.utils import secure_filename
import yaml

from tornado.wsgi import WSGIContainer
from tornado.httpserver import HTTPServer
from tornado.ioloop import IOLoop
import os
import base64

app_port = os.environ.get('APP_PORT', ${app_port})

app = Flask(__name__, template_folder='templates')
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///test.db'
app.config['SECRET_KEY_HMAC'] = 'secret'
app.config['SECRET_KEY_HMAC_2'] = 'am0r3C0mpl3xK3y'
app.secret_key = 'F12Zr47j\3yX R~X@H!jmM]Lwf/,?KT'
app.config['STATIC_FOLDER'] = None

db = SQLAlchemy(app)

class User(db.Model):
    id = db.Column(db.Integer, primary_key = True)
    username = db.Column(db.String(80), unique = True)
    password = db.Column(db.String(80), unique = True)

    def __repr__(self):
        return "<User {0}>".format(self.username)

class Customer(db.Model):
    id = db.Column(db.Integer, primary_key = True)
    first_name = db.Column(db.String(80))
    last_name = db.Column(db.String(80))
    email = db.Column(db.String(80))
    ccn = db.Column(db.String(80), nullable = True)
    username = db.Column(db.String(80))
    password = db.Column(db.String(150))

@app.route('/')
def index():
    return '''
    <!DOCTYPE html>
    <html>
    <head><title>Flask App - Hosted on AWS</title></head>
    <body>
        <h1>Flask Application Successfully Deployed!</h1>
        <p>Your application is running on port ${app_port}</p>
        <p>Deployed with Terraform on AWS EC2</p>
        <hr>
        <p><a href="/health">Health Check</a></p>
    </body>
    </html>
    '''

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.datetime.utcnow().isoformat(),
        'port': app_port
    })

if __name__ == '__main__':
    # Create database tables
    with app.app_context():
        db.create_all()
    
    # Run with Tornado
    http_server = HTTPServer(WSGIContainer(app))
    http_server.listen(app_port, address='0.0.0.0')
    print(f"Flask app running on port {app_port}")
    IOLoop.instance().start()
EOF

# Create templates directory and basic template
mkdir -p templates
cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Flask App - AWS Hosted</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .header { color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; }
        .success { color: #28a745; background: #d4edda; padding: 15px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="header">🚀 Flask Application</h1>
        <div class="success">
            <h2>Successfully Deployed on AWS!</h2>
            <p>Your Flask application is now running on AWS EC2</p>
            <ul>
                <li>Deployed with Terraform</li>
                <li>Running on Amazon Linux 2</li>
                <li>Port: ${app_port}</li>
            </ul>
        </div>
        <hr>
        <p><a href="/health">🔍 Health Check</a></p>
    </div>
</body>
</html>
EOF

# Install Python dependencies
pip3 install --user -r requirements.txt

# Create static directory
mkdir -p static

# Create systemd service file
cat > /etc/systemd/system/flaskapp.service << 'EOF'
[Unit]
Description=Flask Application
After=network.target

[Service]
Type=simple
User=appuser
WorkingDirectory=/opt/app
Environment=APP_PORT=${app_port}
Environment=PYTHONPATH=/opt/app
ExecStart=/usr/bin/python3 /opt/app/app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Set permissions
chown -R appuser:appuser /opt/app
chmod +x /opt/app/app.py

# Install dependencies as appuser
sudo -u appuser pip3 install --user -r /opt/app/requirements.txt

# Enable and start the service
systemctl daemon-reload
systemctl enable flaskapp.service
systemctl start flaskapp.service

# Create a simple health check script
cat > /opt/app/health_check.sh << 'EOF'
#!/bin/bash
curl -f http://localhost:${app_port}/health || exit 1
EOF
chmod +x /opt/app/health_check.sh

# Set up log rotation for app logs
cat > /etc/logrotate.d/flaskapp << 'EOF'
/var/log/flaskapp.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
}
EOF

# Install CloudWatch agent (optional, lightweight monitoring)
yum install -y amazon-cloudwatch-agent

# Create completion marker
echo "Flask app deployment completed at $(date)" > /var/log/deployment-complete.log
echo "App should be accessible on port ${app_port}" >> /var/log/deployment-complete.log

# Final service status check
sleep 10
systemctl status flaskapp.service >> /var/log/deployment-complete.log 