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
const TARGET_RPS = parseInt(__ENV.TARGET_RPS || '50');
const RAMP_UP_TIME = __ENV.RAMP_UP_TIME || '5m';
const SUSTAIN_TIME = __ENV.SUSTAIN_TIME || '10m';
const RAMP_DOWN_TIME = __ENV.RAMP_DOWN_TIME || '5m';
const BASE_URL = __ENV.BASE_URL;

const ESTIMATED_REQ_PER_VU_PER_SEC = 4;
const MAX_VUS = Math.ceil(TARGET_RPS / ESTIMATED_REQ_PER_VU_PER_SEC);

export const options = {
  scenarios: {
    load_test: {
      executor: 'ramping-arrival-rate',
      startRate: 0,
      timeUnit: '1s',
      preAllocatedVUs: Math.ceil(MAX_VUS / 2),
      maxVUs: Math.max(MAX_VUS * 2, 20),
      stages: [
        { duration: RAMP_UP_TIME, target: TARGET_RPS },   // Ramp up
        { duration: SUSTAIN_TIME, target: TARGET_RPS },   // Sustain load
        { duration: RAMP_DOWN_TIME, target: 0 },          // Ramp down
      ],
    },
  },
  thresholds: {
    'http_req_duration{expected_response:true}': ['p(95)<2000'],
    'errors': ['rate<0.02'],
    'http_req_failed': ['rate<0.02'],
  },
  insecureSkipTLSVerify: true,
  noConnectionReuse: false,
  userAgent: 'K6-LoadTest/2.0',
};

export function setup() {
  console.log(`=== K6 Load Test Configuration ===`);
  console.log(`Target RPS: ${TARGET_RPS}`);
  console.log(`Ramp Up: ${RAMP_UP_TIME}`);
  console.log(`Sustain: ${SUSTAIN_TIME}`);
  console.log(`Ramp Down: ${RAMP_DOWN_TIME}`);
  console.log(`Base URL: ${BASE_URL}`);
  console.log(`URLs to test: ${urls.length}`);
  console.log(`Max VUs: ${MAX_VUS}`);
  console.log(`Test start time: ${new Date().toISOString()}`);
  console.log(`===================================`);

  return {
    startTime: new Date().toISOString(),
    targetRps: TARGET_RPS,
    rampUpTime: RAMP_UP_TIME,
    sustainTime: SUSTAIN_TIME,
    rampDownTime: RAMP_DOWN_TIME,
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
  console.log(`\n=== Load Test Completed ===`);
  console.log(`Test end time: ${new Date().toISOString()}`);
  console.log(`Start time: ${data.startTime}`);
  console.log(`Target RPS: ${data.targetRps}`);
  console.log(`Ramp Up: ${data.rampUpTime}`);
  console.log(`Sustain: ${data.sustainTime}`);
  console.log(`Ramp Down: ${data.rampDownTime}`);
  console.log(`============================\n`);
}
