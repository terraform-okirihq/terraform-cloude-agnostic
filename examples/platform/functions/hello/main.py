"""Minimal HTTP function that runs unchanged on AWS Lambda and Google Cloud Functions."""
import json


def handler(event, context=None):
    body = {"message": "hello from the multicloud foundation"}
    # Lambda function URLs expect a dict; Cloud Functions accept a (body, status) tuple.
    if context is not None:
        return {"statusCode": 200, "headers": {"content-type": "application/json"}, "body": json.dumps(body)}
    return json.dumps(body), 200, {"content-type": "application/json"}
