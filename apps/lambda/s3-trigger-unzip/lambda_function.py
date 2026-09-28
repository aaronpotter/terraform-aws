import io
import gzip
import os
import urllib.parse
import boto3

s3 = boto3.client('s3')

# Set the destination bucket name directly or via an environment variable
DESTINATION_BUCKET = 'apotter-lambda-output'

def lambda_handler(event, context):
    # Extract source bucket name and object key from the S3 trigger event
    source_bucket = event['Records'][0]['s3']['bucket']['name']
    key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'], encoding='utf-8')
    
    # Process only files ending with .gz
    if not key.endswith('.gz'):
        print(f"Skipping {key}: Not a .gz file.")
        return {
            'statusCode': 200,
            'body': f"Skipped {key} (not a .gz file)."
        }
    
    try:
        print(f"Processing object s3://{source_bucket}/{key}")
        
        # Download the .gz file from the source bucket
        gz_object = s3.get_object(Bucket=source_bucket, Key=key)
        gz_bytes = gz_object['Body'].read()
        
        # Decompress the gzip content in memory
        with gzip.GzipFile(fileobj=io.BytesIO(gz_bytes), mode='rb') as gz_file:
            decompressed_data = gz_file.read()
            
        # Determine target key (removes .gz extension)
        target_key = key[:-3]
        
        # Upload decompressed data to the destination bucket
        s3.put_object(
            Bucket=DESTINATION_BUCKET,
            Key=target_key,
            Body=decompressed_data
        )
        
        print(f"Successfully decompressed and saved to s3://{DESTINATION_BUCKET}/{target_key}")
        
        s3.delete_object(Bucket=source_bucket, Key=key)
        
        return {
            'statusCode': 200,
            'body': f"Successfully extracted {key} from {source_bucket} to {DESTINATION_BUCKET}/{target_key}"
        }

    except Exception as e:
        print(f"Error processing {key} from bucket {source_bucket}: {str(e)}")
        raise e