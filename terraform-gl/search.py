import boto3
import json
import re
from pinecone import Pinecone
from openai import OpenAI
import logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

secret = None

def get_secrets():
    global secret
    if secret is None:
        client = boto3.client('secretsmanager')
        try:
            response = client.get_secret_value(SecretId='gl-search-api-secret')
            secret = json.loads(response['SecretString'])
        except Exception as e:
            logger.error(f"Error retrieving secret: {e}")
            raise e

def embed(text):
    get_secrets()
    try:
        openai_api_key = secret.get('openai_api_key')
        if not openai_api_key:
            raise ValueError("OpenAI API key is missing from secrets")

        client = OpenAI(api_key=openai_api_key)
        response = client.embeddings.create(
            input=text,
            model="text-embedding-3-large"
        )
        return response.data[0].embedding
    except Exception as e:
        logger.error(f"Error generating embedding: {e}")
        raise e

def get_namespace(user_text):

    default_namespace = "GL-1.3"
    pattern = re.compile(r'^(GL)[-\.]')
    return user_text if pattern.match(user_text) else default_namespace
    
def lambda_handler(event, context):
    try:
  
        get_secrets()
        
        pinecone_api_key = secret.get('pinecone_api_key')
        if not pinecone_api_key:
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Pinecone API key is missing from secrets'})
            }

        body = json.loads(event.get('body', '{}'))
        query = body.get('allWordsQuery', '')
        if not query:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'missing query'})
            }

        k = body.get('size', 10)  # Default value for k
        index_name = 'content'  # Don't allow caller to change this
        
        namespace = get_namespace(body.get('namespace', ''))

        kwargs = {'namespace': namespace, 'include_metadata': True}
    
        filter = body.get('filter', None)
        if filter is not None:
            kwargs['filter'] = filter

        logger.info(f"Query parameters: {kwargs}")
       
        pc = Pinecone(api_key=pinecone_api_key)
        index = pc.Index(index_name)

        embedding = embed(query)
        res = index.query(vector=embedding, top_k=k, **kwargs)
        
        
        result_data = {
                'totalHits': k,
                'allWordsQuery': query,
                'hits': [ {
                        "subitemId" : match.metadata['subitemId'],
                        "title" : match.metadata['title'],
                        "subtitle" : match.metadata['subtitle'],
                        "subitemVersion" : int(match.metadata['subitemVersion']),
                        "itemId" : match.metadata['itemId'],
                        "itemVersion" : int(match.metadata['itemVersion']),
                        "snippet" : match.metadata['text'],
                        "offsets" : match.metadata['offsets']
                     } for match in res.matches ]
        }
        return {
            'statusCode': 200,
            'body': json.dumps(result_data)
        }
    except Exception as e:
        logger.error(f"Error in lambda_handler: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


