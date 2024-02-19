import { MAX_UPLOAD_SIZE_BYTES } from "./uploads";

export default ({ env }) => {
  let result: any = {
    upload: {
      config: {
        sizeLimit: MAX_UPLOAD_SIZE_BYTES
      }
    }
  };
  const connection_string = env('COMMUNICATION_SERVICE_CONNECTION_STRING');
  const fallback_email = env('FALLBACK_EMAIL');
  if (connection_string && fallback_email) {
    result.email = {
      config: {
        provider: 'strapi-provider-email-azure',
        providerOptions: {
          endpoint: connection_string,
        },
        settings: {
          defaultFrom: fallback_email,
        },
      },
    };
  }
  return result;
};
