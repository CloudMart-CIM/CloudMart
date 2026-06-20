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
  http.get('http://k8s-cloudmar-cloudmar-ba92bd1afd-1163610694.ap-south-1.elb.amazonaws.com/api/products');
  sleep(0.1);
}