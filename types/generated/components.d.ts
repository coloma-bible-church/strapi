import type { Schema, Attribute } from '@strapi/strapi';

export interface SermonScriptureScripture extends Schema.Component {
  collectionName: 'components_sermon_scripture_scriptures';
  info: {
    displayName: 'Scripture';
    description: '';
  };
  attributes: {
    reference: Attribute.String & Attribute.Required;
  };
}

declare module '@strapi/types' {
  export module Shared {
    export interface Components {
      'sermon-scripture.scripture': SermonScriptureScripture;
    }
  }
}
