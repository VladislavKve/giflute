def update(self):
            rquid = str(uuid.uuid4())
            url = 'https://ngw.devices.sberbank.ru:9443/api/v2/oauth'
            headers = {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json',
                'RqUID': rquid,
                'Authorization': 'Basic ' + self.authorization_key   
            }
            data = {'scope': 'GIGACHAT_API_PERS'}
            response = requests.request("POST", url, headers=headers, data=data, verify=False)
            if response.status_code == 200:
                result = response.json()
                self.access_token = result.get('access_token')
                self.expires_at = result.get('expires_at')
                self.parent.headers['Authorization'] = f"Bearer {self.access_token}"
                return result
            else:
                logger.error(f'Request failed with status {response.status_code}')
                return None