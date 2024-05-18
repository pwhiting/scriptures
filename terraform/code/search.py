import boto3
import json
from pinecone import Pinecone
from openai import OpenAI

secret = None


def get_secrets():
    global secret
    if secret is None:
        client = boto3.client('secretsmanager')
        try:
            response = client.get_secret_value(SecretId='search-api-secret')
            secret = json.loads(response['SecretString'])
        except Exception as e:
            print(f"Error retrieving secret: {e}")
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
        print(f"Error generating embedding: {e}")
        raise e

    
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
        query = body.get('query', '')
        if not query:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'missing query'})
            }

        k = body.get('k', 10)  # Default value for k
        index_name = 'content'  # Don't allow caller to change this
        
        #namespace = body.get('namespace', 'reference.1.1')  # Default value for namespace
        namespace = "Scriptures-1.1"
        kwargs = {'namespace':namespace,'include_metadata':True}
    
        filter = body.get('filter',None)
        if filter is not None:
            kwargs['filter'] = filter

        print (kwargs)
        pc = Pinecone(api_key=pinecone_api_key)
        index = pc.Index(index_name)

        embedding = embed(query)
        res = index.query(vector=embedding,top_k=k,**kwargs)
        
        result_data = {
            'matches': [
                {
                    'score': match.score,
                    'metadata': match.metadata
                } for match in res.matches
            ]
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(result_data)
        }
    except Exception as e:
        print(f"Error in lambda_handler: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
