---
title: "Handling Redirects with CloudFront Functions"
date: 2022-03-01
draft: false
externalUrl: https://tech.mybuilder.com/handling-redirects-with-cloudfront-functions/
---

Over the years we've seen countless methods for handling redirects in web applications. From the Apache rewrite rule to
AWS ALBs, Lambda@Edge, and even with S3 object metadata. In this post I'm going to share yet another method that we've
recently started using at MyBuilder: CloudFront Functions.

<!--more-->

<meta http-equiv="refresh" content="0; url=https://tech.mybuilder.com/handling-redirects-with-cloudfront-functions/">

We recently moved our entire web stack to AWS Lambda using the popular [Bref](https://bref.sh) project. Replacing our
traditional LAMP stack with a Serverless approach feels like a great step forward, but without Apache we needed a new
way to ensure all traffic on mybuilder.com gets redirected and served from our canonical domain, [www.mybuilder.com](https://www.mybuilder.com).

Last year AWS released CloudFront Functions, a lightweight compute platform that runs on the CloudFront edge network.
There are a few performance related limitations, such as a one millisecond max execution time, but it's ideal for simple
use cases like redirects.

All we have to do is define a JavaScript handler function (ECMAScript 5.1 at the time of writing) that inspects the
request and returns a redirect response if necessary. CloudFront passes us an [event object](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/functions-event-structure.html)
containing the request, from which we can pluck out the `Host` header for inspection:

```js
function handler(event) {
  var host =
    (event.request.headers.host &&
      event.request.headers.host.value) ||
    '';

  if (host.indexOf('www.') === 0) {
    return event.request;
  }

  var queryString = Object.keys(event.request.querystring)
    .map(key => key + '=' + event.request.querystring[key].value)
    .join('&');

  return {
    statusCode: 301,
    statusDescription: 'Moved Permanently',
    headers: {
      location: {
        value:
          'https://www.' +
          host +
          event.request.uri +
          (queryString.length > 0 ? '?' + queryString : ''),
      },
    },
  };
}
```

If the incoming request already begins `www.`, the original request object is returned and CloudFront sends it to the
origin as usual. Otherwise, we construct a new request URI and tell CloudFront to issue a redirect response instead.

Inspecting the headers with cURL confirms it's being handled by CloudFront Functions:

```bash
$ curl -I https://mybuilder.com
HTTP/2 301
server: CloudFront
location: https://www.mybuilder.com/
x-cache: FunctionGeneratedResponse from cloudfront
...
```

## Infrastructure as Code

The story doesn't end there, though. We're also pretty big believers in automation at MyBuilder, so it would be remiss
of me not to include how we codify this part of our infrastructure. We use tools like Terraform whenever possible to
take the pain out of manual configuration.

The following Terraform configuration shows how we can reference the JavaScript above to provision a CloudFront Function
and attach it to a CloudFront Distribution:

```hcl
resource "aws_cloudfront_function" "www_redirect" {
  name    = "www-redirect"
  runtime = "cloudfront-js-1.0"
  code    = file("${path.module}/www-redirect.js")
  publish = true
}

resource "aws_cloudfront_distribution" "main" {
  ...

  default_cache_behavior {
    ...

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.www_redirect.arn
    }
  }
}
```

## Conclusion

Our move to CloudFront Functions has benefited us in more ways than one. Not only is it super cheap (a sixth of the cost
of Lambda@Edge!), but it also feels more correct to isolate this concern at an infrastructural level, rather than within
our own runtime.

We've been using CloudFront to handle the web delivery part of our stack for a while, and that's unlikely to change any
time soon. So, while there will undoubtedly be another method for handling redirects just around the corner, it does
feel like we've landed on something that will stick.
