import logging
import azure.functions as func
import json

def main(req: func.HttpRequest) -> func.HttpResponse:
    your_message = req.params.get("message")

    if "hello" in your_message.lower() or "world" in your_message.lower():
        return func.HttpResponse(body='{ "error": "Think of a better message" }', status_code=422)

    return func.HttpResponse(body=json.dumps(your_message), status_code=200)
