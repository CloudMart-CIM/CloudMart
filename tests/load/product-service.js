// load-test.js
import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 50 },   // ramp up
    { duration: '1m',  target: 200 },  // sustain load
    { duration: '30s', target: 0 },    // ramp down
  ],
};

export default function () {
  http.get('http://localhost:8001/products');
  sleep(0.1);
}