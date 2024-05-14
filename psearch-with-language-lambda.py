import os
import json
import numpy as np
import boto3
from langchain_openai import OpenAIEmbeddings
from openai import OpenAI
from pinecone import Pinecone

def lambda_handler(event, context):
  
  print(event)
  body = json.loads(event['body'])
    
  # Extract the 'query' value
  query = body['query']
  
  client = OpenAI()
  api_key = os.getenv("PINECONE_API_KEY")
  pc = Pinecone(api_key=api_key)
  index = pc.Index("scriptures")

  def translate(text, lang):
    try:
      answer = client.chat.completions.create(
        messages=[{
          "role": "user",
          "content": f"Translate the following English text to {lang}: {text}",
        }],
        model="gpt-3.5-turbo",
      )
      return answer.choices[0].message.content
    except Exception as e:
      print(f"An error occurred: {e}")
      return None

  def embed(text):
    response = client.embeddings.create(
      input=text,
      model="text-embedding-ada-002"
    )
    return response.data[0].embedding

  def lang_vec(q):
    squery = translate(q, "spanish")
    mquery = translate(q, "mandarin")
    embeds = [embed(query), embed(squery), embed(mquery)]
    return np.mean(embeds, axis=0).tolist()

  results = index.query(vector=lang_vec(query), top_k=10, include_metadata=True)
  response = []
  for result in results['matches']:
    print(result)
    response.append({
      'score': result['score'],
      'meta': result['metadata']
    })

  return {
    'statusCode': 200,
    'body': json.dumps(response)
  }
