import boto3
import json
import os
import uuid

textract_client = boto3.client('textract')
sagemaker_client = boto3.client('sagemaker-runtime')
dynamodb_client = boto3.client('dynamodb')

INVOICE_BUCKET = os.environ['INVOICE_BUCKET_NAME']
DB_TABLE_NAME = os.environ['DB_TABLE_NAME']
SAGEMAKER_ENDPOINT = os.environ['SAGEMAKER_ENDPOINT_NAME']

def lambda_handler(event, context):
    
    body = json.loads(event.get('body', '{}'))
    file_key = body.get('key')
    
    if not file_key:
        return {'statusCode': 400, 'body': json.dumps('Falta la "key" del archivo S3')}

    try:
        response = textract_client.analyze_expense(
            DocumentLocation={'S3Object': {'Bucket': INVOICE_BUCKET, 'Name': file_key}}
        )
        
        extracted_data = parse_textract_response(response)
        
        status = "APROBADO" # Estado por defecto
        
        if SAGEMAKER_ENDPOINT != "none":
            payload_data = [ float(extracted_data.get('TOTAL', 0.0)) ]
            
            sagemaker_response = sagemaker_client.invoke_endpoint(
                EndpointName=SAGEMAKER_ENDPOINT,
                ContentType='application/json',
                Body=json.dumps(payload_data)
            )
            
            result = json.loads(sagemaker_response['Body'].read())
            if result == 1:
                status = "REVISAR (Posible Fraude)"
        
        # 5. Guardar todo en DynamoDB
        invoice_id = str(uuid.uuid4())
        item = {
            'invoiceId': {'S': invoice_id},
            's3_key': {'S': file_key},
            'status': {'S': status},
            'vendor': {'S': extracted_data.get('VENDOR_NAME', 'N/A')},
            'total': {'N': str(extracted_data.get('TOTAL', 0.0))}
        }
        
        dynamodb_client.put_item(TableName=DB_TABLE_NAME, Item=item)

        return {
            'statusCode': 200,
            'headers': { 'Access-Control-Allow-Origin': '*' },
            'body': json.dumps(item) 
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': { 'Access-Control-Allow-Origin': '*' },
            'body': json.dumps({'error': str(e)})
        }

def parse_textract_response(response):
    data = {}
    for doc in response.get('ExpenseDocuments', []):
        for field in doc.get('SummaryFields', []):
            field_type = field.get('Type', {}).get('Text')
            field_value = field.get('ValueDetection', {}).get('Text')
            
            if field_type == 'TOTAL':
                data['TOTAL'] = field_value.replace('$', '')
            if field_type == 'VENDOR_NAME':
                data['VENDOR_NAME'] = field_value
                
    return data