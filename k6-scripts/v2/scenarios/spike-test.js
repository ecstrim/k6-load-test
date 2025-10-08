import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import { SharedArray } from 'k6/data';

// Custom metrics
const errorRate = new Rate('errors');
const successRate = new Rate('success');
const requestDuration = new Trend('request_duration');
const totalRequests = new Counter('total_requests');

// Load URLs from JSON file
const urls = new SharedArray('urls', function() {
  const urlData = JSON.parse(open(__ENV.URL_DATA_PATH || '/data/urls-1.json'));
  return urlData.urls;
});

// Test configuration from environment variables
const BASELINE_RPS = parseInt(__ENV.TARGET_RPS || '50');
const SPIKE_MULTIPLIER = parseInt(__ENV.SPIKE_MULTIPLIER || '5');
const SPIKE_DURATION = __ENV.SPIKE_DURATION || '30s';
const DURATION = __ENV.DURATION || '2m';
const BASE_URL = __ENV.BASE_URL;

const SPIKE_RPS = BASELINE_RPS * SPIKE_MULTIPLIER;
const ESTIMATED_REQ_PER_VU_PER_SEC = 4;
const BASELINE_VUS = Math.ceil(BASELINE_RPS / ESTIMATED_REQ_PER_VU_PER_SEC);
const SPIKE_VUS = Math.ceil(SPIKE_RPS / ESTIMATED_REQ_PER_VU_PER_SEC);

export const options = {
  scenarios: {
    spike_test: {
      executor: 'ramping-arrival-rate',
      startRate: BASELINE_RPS,
      timeUnit: '1s',
      preAllocatedVUs: BASELINE_VUS,
      maxVUs: Math.max(SPIKE_VUS * 2, 50),
      stages: [
        { duration: '1m', target: BASELINE_RPS },      // Baseline traffic
        { duration: '10s', target: SPIKE_RPS },        // Spike up
        { duration: SPIKE_DURATION, target: SPIKE_RPS }, // Sustained spike
        { duration: '10s', target: BASELINE_RPS },     // Spike down
        { duration: '30s', target: BASELINE_RPS },     // Recovery period
      ],
    },
  },
  thresholds: {
    'http_req_duration{expected_response:true}': ['p(95)<2000'],
    'errors': ['rate<0.05'], // Allow higher error rate during spike
    'http_req_failed': ['rate<0.05'],
  },
  insecureSkipTLSVerify: true,
  noConnectionReuse: false,
  userAgent: 'K6-SpikeTest/2.0',
};

export function setup() {
  console.log(`=== K6 Spike Test Configuration ===`);
  console.log(`Baseline RPS: ${BASELINE_RPS}`);
  console.log(`Spike RPS: ${SPIKE_RPS} (${SPIKE_MULTIPLIER}x multiplier)`);
  console.log(`Spike Duration: ${SPIKE_DURATION}`);
  console.log(`Total Duration: ${DURATION}`);
  console.log(`Base URL: ${BASE_URL}`);
  console.log(`URLs to test: ${urls.length}`);
  console.log(`Test start time: ${new Date().toISOString()}`);
  console.log(`====================================`);

  return {
    startTime: new Date().toISOString(),
    baselineRps: BASELINE_RPS,
    spikeRps: SPIKE_RPS,
  };
}

export default function(data) {
  const urlPath = urls[Math.floor(Math.random() * urls.length)];
  const url = `${BASE_URL}${urlPath}`;

  const params = {
    headers: {
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      'Accept-Language': 'en-US,en;q=0.9',
    },
    timeout: '30s',
    tags: { name: urlPath },
  };

  const response = http.get(url, params);

  totalRequests.add(1);
  requestDuration.add(response.timings.duration);

  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 2000ms': (r) => r.timings.duration < 2000,
    'response has body': (r) => r.body && r.body.length > 0,
  });

  if (success) {
    successRate.add(1);
    errorRate.add(0);
  } else {
    successRate.add(0);
    errorRate.add(1);
    console.error(`Request failed: ${url} - Status: ${response.status}`);
  }
}

export function teardown(data) {
  console.log(`\n=== Spike Test Completed ===`);
  console.log(`Test end time: ${new Date().toISOString()}`);
  console.log(`Baseline RPS: ${data.baselineRps}`);
  console.log(`Spike RPS: ${data.spikeRps}`);
  console.log(`============================\n`);
}
