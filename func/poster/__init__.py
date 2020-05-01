import logging
import azure.functions as func
import json

def main(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(body=f"Success! Now please take the body back {req.get_body()}", status_code=200)
