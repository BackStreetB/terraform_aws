from prometheus_client import start_http_server, Gauge
import time
import subprocess

nginx_up = Gauge('nginx_up', 'Nginx running status (1=up, 0=down)')

def check_nginx():
    try:
        subprocess.check_output(['systemctl', 'is-active', '--quiet', 'nginx'])
        return 1
    except subprocess.CalledProcessError:
        return 0

if __name__ == '__main__':
    start_http_server(8000)  # Expose metrics at http://localhost:8000/metrics
    while True:
        status = check_nginx()
        nginx_up.set(status)
        time.sleep(15) 