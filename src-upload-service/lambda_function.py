import boto3
import json
import uuid
import os

BUCKET_NAME = os.environ['INVOICE_BUCKET_NAME']
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    try:
        body = json.loads(event.get('body', '{}'))
        content_type = body.get('contentType', 'application/octet-stream')
        
        file_key = f"uploads/{uuid.uuid4()}-{body.get('fileName', 'file')}"

        presigned_url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': BUCKET_NAME,
                'Key': file_key,
                'ContentType': content_type
            },
            ExpiresIn=3600  
        )

        return {
            'statusCode': 200,
            'headers': { 'Access-Control-Allow-Origin': '*' },
            'body': json.dumps({
                'uploadURL': presigned_url,
                'key': file_key  
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': { 'Access-Control-Allow-Origin': '*' },
            'body': json.dumps({'error': str(e)})
        }