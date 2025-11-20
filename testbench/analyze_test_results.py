#!/usr/bin/env python3
"""
Test Results Analyzer for SPI-Coax System
Analyzes test output and generates comprehensive HTML reports
"""

import re
import sys
import os
from datetime import datetime
from pathlib import Path

class TestResultAnalyzer:
    def __init__(self, log_file, output_file):
        self.log_file = Path(log_file)
        self.output_file = Path(output_file)
        self.test_results = {}
        self.statistics = {}
        self.parse_log()

    def parse_log(self):
        """Parse the test log file and extract results"""
        try:
            with open(self.log_file, 'r') as f:
                content = f.read()
                self.extract_test_results(content)
                self.extract_statistics(content)
                self.extract_performance_metrics(content)
        except FileNotFoundError:
            print(f"Error: Log file {self.log_file} not found")
            sys.exit(1)

    def extract_test_results(self, content):
        """Extract individual test results"""
        # Look for test scenario patterns
        test_patterns = [
            r"Running test scenario: (\w+)",
            r"INFO: Running test scenario: (\w+)",
            r"(\w+) test: (PASSED|FAILED)",
            r"✓ (\w+) test PASSED",
            r"✗ (\w+) test FAILED"
        ]

        for pattern in test_patterns:
            matches = re.findall(pattern, content, re.IGNORECASE)
            for match in matches:
                if isinstance(match, tuple):
                    test_name = match[0]
                    status = match[1] if len(match) > 1 else "UNKNOWN"
                else:
                    test_name = match
                    status = "UNKNOWN"

                self.test_results[test_name] = status

    def extract_statistics(self, content):
        """Extract test statistics"""
        stat_patterns = {
            'total_frames_sent': r'Total Frames Sent: (\d+)',
            'total_frames_received': r'Total Frames Received: (\d+)',
            'total_crc_errors': r'Total CRC Errors: (\d+)',
            'total_frame_errors': r'Total Frame Errors: (\d+)',
            'total_sync_losses': r'Total Sync Losses: (\d+)',
            'error_count': r'Errors?[:\s]+(\d+)',
            'warning_count': r'Warnings?[:\s]+(\d+)',
            'test_duration': r'Duration:\s*([\d.]+)\s*ms',
            'throughput': r'Throughput[^:]*:\s*([\d.]+)\s*kbps'
        }

        for key, pattern in stat_patterns.items():
            match = re.search(pattern, content, re.IGNORECASE)
            if match:
                try:
                    self.statistics[key] = float(match.group(1))
                except ValueError:
                    self.statistics[key] = match.group(1)

    def extract_performance_metrics(self, content):
        """Extract performance-specific metrics"""
        perf_patterns = {
            'frame_success_rate': r'frame success rate[^:]*:\s*([\d.]+)%',
            'error_rate': r'error rate[^:]*:\s*([\d.]+)%',
            'lock_time': r'lock.*time[^:]*:\s*([\d.]+)\s*',
            'recovery_time': r'recovery.*time[^:]*:\s*([\d.]+)\s*'
        }

        for key, pattern in perf_patterns.items():
            match = re.search(pattern, content, re.IGNORECASE)
            if match:
                self.statistics[key] = float(match.group(1))

    def calculate_derived_metrics(self):
        """Calculate derived performance metrics"""
        if 'total_frames_received' in self.statistics and 'total_frames_sent' in self.statistics:
            if self.statistics['total_frames_sent'] > 0:
                success_rate = (self.statistics['total_frames_received'] /
                               self.statistics['total_frames_sent']) * 100
                self.statistics['calculated_success_rate'] = success_rate

        if 'total_crc_errors' in self.statistics and 'total_frames_sent' in self.statistics:
            if self.statistics['total_frames_sent'] > 0:
                error_rate = (self.statistics['total_crc_errors'] /
                             self.statistics['total_frames_sent']) * 100
                self.statistics['calculated_error_rate'] = error_rate

    def generate_html_report(self):
        """Generate comprehensive HTML report"""
        self.calculate_derived_metrics()

        html_content = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SPI-Coax Production Test Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }}
        .container {{ max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
        .header {{ text-align: center; border-bottom: 2px solid #333; padding-bottom: 20px; margin-bottom: 30px; }}
        .summary {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }}
        .metric {{ background: #f8f9fa; padding: 15px; border-radius: 5px; border-left: 4px solid #007bff; }}
        .metric h3 {{ margin: 0 0 10px 0; color: #333; }}
        .metric .value {{ font-size: 24px; font-weight: bold; color: #007bff; }}
        .metric .unit {{ font-size: 14px; color: #666; }}
        .test-results {{ margin-bottom: 30px; }}
        .test-item {{ display: flex; justify-content: space-between; align-items: center; padding: 10px; border-bottom: 1px solid #eee; }}
        .test-item:last-child {{ border-bottom: none; }}
        .test-name {{ font-weight: bold; }}
        .test-status {{ padding: 4px 12px; border-radius: 4px; color: white; font-size: 12px; }}
        .status-passed {{ background: #28a745; }}
        .status-failed {{ background: #dc3545; }}
        .status-unknown {{ background: #6c757d; }}
        .details {{ background: #f8f9fa; padding: 20px; border-radius: 5px; margin-bottom: 20px; }}
        .chart-container {{ margin: 20px 0; text-align: center; }}
        .footer {{ text-align: center; margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; }}
        .alert {{ padding: 15px; border-radius: 4px; margin: 10px 0; }}
        .alert-success {{ background: #d4edda; border: 1px solid #c3e6cb; color: #155724; }}
        .alert-danger {{ background: #f8d7da; border: 1px solid #f5c6cb; color: #721c24; }}
        .alert-warning {{ background: #fff3cd; border: 1px solid #ffeaa7; color: #856404; }}
        table {{ width: 100%; border-collapse: collapse; margin: 20px 0; }}
        th, td {{ padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }}
        th {{ background: #f8f9fa; font-weight: bold; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔬 SPI-Coax Production Test Report</h1>
            <p>Generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            <p><strong>Test Log:</strong> {self.log_file.name}</p>
        </div>

        <div class="summary">
            {self.generate_summary_cards()}
        </div>

        <div class="test-results">
            <h2>📋 Test Results Summary</h2>
            {self.generate_test_results_table()}
        </div>

        <div class="details">
            <h2>📊 Detailed Statistics</h2>
            {self.generate_statistics_table()}
        </div>

        {self.generate_performance_section()}

        {self.generate_alerts_section()}

        <div class="footer">
            <p>Report generated by SPI-Coax Test Results Analyzer</p>
            <p>For questions or issues, please check the test log files</p>
        </div>
    </div>
</body>
</html>
        """

        # Ensure output directory exists
        self.output_file.parent.mkdir(parents=True, exist_ok=True)

        with open(self.output_file, 'w') as f:
            f.write(html_content)

        print(f"✅ HTML report generated: {self.output_file}")

    def generate_summary_cards(self):
        """Generate summary metric cards"""
        cards = []

        # Overall test status
        passed_tests = sum(1 for status in self.test_results.values() if status.upper() == 'PASSED')
        total_tests = len(self.test_results)

        cards.append(f"""
        <div class="metric">
            <h3>Overall Status</h3>
            <div class="value">{passed_tests}/{total_tests}</div>
            <div class="unit">Tests Passed</div>
        </div>
        """)

        # Frame success rate
        if 'calculated_success_rate' in self.statistics:
            success_rate = self.statistics['calculated_success_rate']
            status_class = 'alert-success' if success_rate > 95 else 'alert-warning' if success_rate > 90 else 'alert-danger'
            cards.append(f"""
            <div class="metric">
                <h3>Frame Success Rate</h3>
                <div class="value">{success_rate:.2f}%</div>
                <div class="unit">Data Integrity</div>
            </div>
            """)

        # Error rate
        if 'calculated_error_rate' in self.statistics:
            error_rate = self.statistics['calculated_error_rate']
            cards.append(f"""
            <div class="metric">
                <h3>Error Rate</h3>
                <div class="value">{error_rate:.4f}%</div>
                <div class="unit">Error Detection</div>
            </div>
            """)

        # Throughput
        if 'throughput' in self.statistics:
            throughput = self.statistics['throughput']
            cards.append(f"""
            <div class="metric">
                <h3>Throughput</h3>
                <div class="value">{throughput:.1f}</div>
                <div class="unit">kbps</div>
            </div>
            """)

        # Test duration
        if 'test_duration' in self.statistics:
            duration = self.statistics['test_duration']
            cards.append(f"""
            <div class="metric">
                <h3>Test Duration</h3>
                <div class="value">{duration:.1f}</div>
                <div class="unit">ms</div>
            </div>
            """)

        return '\n'.join(cards)

    def generate_test_results_table(self):
        """Generate test results table"""
        if not self.test_results:
            return "<p>No test results found in log file.</p>"

        rows = []
        for test_name, status in self.test_results.items():
            status_class = 'status-passed' if status.upper() == 'PASSED' else 'status-failed' if status.upper() == 'FAILED' else 'status-unknown'
            rows.append(f"""
            <div class="test-item">
                <span class="test-name">{test_name}</span>
                <span class="test-status {status_class}">{status}</span>
            </div>
            """)

        return '\n'.join(rows)

    def generate_statistics_table(self):
        """Generate detailed statistics table"""
        if not self.statistics:
            return "<p>No statistics found in log file.</p>"

        rows = []
        for key, value in self.statistics.items():
            display_key = key.replace('_', ' ').title()
            if isinstance(value, float):
                if 'rate' in key.lower():
                    display_value = f"{value:.4f}%"
                elif 'time' in key.lower() or 'duration' in key.lower():
                    display_value = f"{value:.2f} ms"
                elif 'throughput' in key.lower():
                    display_value = f"{value:.1f} kbps"
                else:
                    display_value = f"{value:.2f}"
            else:
                display_value = str(value)

            rows.append(f"""
            <tr>
                <td>{display_key}</td>
                <td>{display_value}</td>
            </tr>
            """)

        return f"""
        <table>
            <thead>
                <tr>
                    <th>Metric</th>
                    <th>Value</th>
                </tr>
            </thead>
            <tbody>
                {''.join(rows)}
            </tbody>
        </table>
        """

    def generate_performance_section(self):
        """Generate performance analysis section"""
        performance_metrics = [k for k in self.statistics.keys() if 'rate' in k or 'throughput' in k or 'duration' in k]

        if not performance_metrics:
            return ""

        return f"""
        <div class="details">
            <h2>⚡ Performance Analysis</h2>
            <div class="chart-container">
                <h3>Key Performance Indicators</h3>
                <ul>
                    {''.join([f'<li><strong>{k.replace("_", " ").title()}:</strong> {self.statistics[k]:.4f}</li>' for k in performance_metrics])}
                </ul>
            </div>
        </div>
        """

    def generate_alerts_section(self):
        """Generate alerts and warnings section"""
        alerts = []

        # Check for high error rates
        if 'calculated_error_rate' in self.statistics:
            error_rate = self.statistics['calculated_error_rate']
            if error_rate > 1.0:
                alerts.append(f'<div class="alert alert-danger"><strong>High Error Rate:</strong> {error_rate:.4f}% (threshold: 1.0%)</div>')
            elif error_rate > 0.1:
                alerts.append(f'<div class="alert alert-warning"><strong>Elevated Error Rate:</strong> {error_rate:.4f}% (monitor recommended)</div>')

        # Check for low success rates
        if 'calculated_success_rate' in self.statistics:
            success_rate = self.statistics['calculated_success_rate']
            if success_rate < 95.0:
                alerts.append(f'<div class="alert alert-danger"><strong>Low Success Rate:</strong> {success_rate:.2f}% (threshold: 95.0%)</div>')

        # Check for failed tests
        failed_tests = [name for name, status in self.test_results.items() if status.upper() == 'FAILED']
        if failed_tests:
            alerts.append(f'<div class="alert alert-danger"><strong>Failed Tests:</strong> {", ".join(failed_tests)}</div>')

        if not alerts:
            return '<div class="alert alert-success"><strong>All Systems Normal:</strong> No critical issues detected</div>'

        return f'<div class="details"><h2>⚠️ Alerts and Warnings</h2>{"".join(alerts)}</div>'

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 analyze_test_results.py <log_file> <output_html>")
        sys.exit(1)

    log_file = sys.argv[1]
    output_file = sys.argv[2]

    analyzer = TestResultAnalyzer(log_file, output_file)
    analyzer.generate_html_report()

if __name__ == "__main__":
    main()