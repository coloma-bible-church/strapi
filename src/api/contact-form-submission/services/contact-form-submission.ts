/**
 * contact-form-submission service
 */

import { factories } from '@strapi/strapi';
import { env, errors } from '@strapi/utils';

const { ApplicationError } = errors;

// https://docs.strapi.io/dev-docs/plugins/email#using-the-sendtemplatedemail-function
// https://lodash.com/docs/4.17.15#template
const emailTemplate = {
  subject: 'New contact form submission from <%- email %>',
  text: 'Name: <%- name %>\nEmail: <%- email %>\n\n<%- message %>\n\n(Sent using the contact form at <%- link %>)',
  html: `
  <% _.forEach(messageLines, function(line) { %><p><%- line %></p><% }) %>
  <p><sub><i><%- name %> (<%- email %>) sent this message using the contact form at <a href="<%- link %>"><%- link %></a></i></sub></p>`
};

export default factories.createCoreService(
  'api::contact-form-submission.contact-form-submission',
  ({ strapi }) => ({
    async create(params) {
      const result = await super.create(params);
      try {
        const to = env.json('CONTACT_TO'); // See format of "to" property here: https://www.npmjs.com/package/@azure/communication-email
        if (to) {
          strapi.log.info('Sending contact form notification email...');
          const emailPromise: Promise<any> = strapi
            .plugins['email']
            .services['email']
            .sendTemplatedEmail(
              {
                to: to,
                cc: { address: result.email, displayName: result.name },
                replyTo: { address: result.email, displayName: result.name }
              },
              emailTemplate,
              {
                name: result.name,
                email: result.email,
                message: result.message,
                messageLines: result.message.split('\n'),
                link: env('CONTACT_LINK')
              });
          emailPromise.then(
            email => strapi.log.info(`Sent contact form notification email: ${JSON.stringify(email)}`),
            error => strapi.log.error(`Failed to send contact form notification email: ${JSON.stringify(error)}`)
          );
        } else {
          strapi.log.info('Not sending contact form notification email because CONTACT_TO is not set.');
        }
        return result;
      } catch (error) {
        strapi.log.error(error);
        throw new ApplicationError('Something went wrong');
      }
    }
  }));
