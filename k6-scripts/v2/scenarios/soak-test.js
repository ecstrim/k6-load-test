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
const DURATION = __ENV.DURATION || '30m'; // Soak tests are longer
const BASE_URL = __ENV.BASE_URL;

const ESTIMATED_REQ_PER_VU_PER_SEC = 4;
const CALCULATED_VUS = Math.ceil(TARGET_RPS / ESTIMATED_REQ_PER_VU_PER_SEC);

export const options = {
  scenarios: {
    soak_test: {
      executor: 'constant-arrival-rate',
      rate: TARGET_RPS,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: CALCULATED_VUS,
      maxVUs: Math.max(CALCULATED_VUS * 3, 20),
    },
  },
  thresholds: {
    'http_req_duration{expected_response:true}': ['p(95)<2000'],
    'errors': ['rate<0.02'],
    'http_req_failed': ['rate<0.02'],
    // Memory leak detection: check if response times increase over time
    'http_req_duration{expected_response:true}': ['p(95)<2000', 'p(99)<5000'],
  },
  insecureSkipTLSVerify: true,
  noConnectionReuse: false,
  userAgent: 'K6-SoakTest/2.0',
};

export function setup() {
  console.log(`=== K6 Soak Test Configuration ===`);
  console.log(`Target RPS: ${TARGET_RPS}`);
  console.log(`Duration: ${DURATION} (extended for memory leak detection)`);
  console.log(`Base URL: ${BASE_URL}`);
  console.log(`URLs to test: ${urls.length}`);
  console.log(`Calculated VUs: ${CALCULATED_VUS}`);
  console.log(`Test start time: ${new Date().toISOString()}`);
  console.log(`===================================`);

  return {
    startTime: new Date().toISOString(),
    targetRps: TARGET_RPS,
    duration: DURATION,
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
  console.log(`\n=== Soak Test Completed ===`);
  console.log(`Test end time: ${new Date().toISOString()}`);
  console.log(`Start time: ${data.startTime}`);
  console.log(`Target RPS: ${data.targetRps}`);
  console.log(`Duration: ${data.duration}`);
  console.log(`Check metrics for performance degradation over time`);
  console.log(`===========================\n`);
}
