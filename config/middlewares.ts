import { MAX_UPLOAD_SIZE_BYTES } from "./uploads";

export default [
  'strapi::logger',
  'strapi::errors',
  'strapi::security',
  'strapi::cors',
  'strapi::poweredBy',
  'strapi::query',
  {
    name: 'strapi::body',
    config: {
      formidable: {
        maxFileSize: MAX_UPLOAD_SIZE_BYTES
      }
    }
  },
  'strapi::session',
  'strapi::favicon',
  'strapi::public',
];
