from providers import register_provider
from providers.base import ProviderProfile

register_provider(ProviderProfile(name="store-provider", base_url="http://127.0.0.1:9/v1"))
