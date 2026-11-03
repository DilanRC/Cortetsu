#include <security/pam_appl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* Runs one pam_authenticate() against a PAM stack in CONFDIR.
 * usage: pam-cancel-probe CONFDIR SERVICE USER MODE
 *   MODE cancel        the conversation fails, as polkit-agent-helper-1 does
 *                      when the agent cancels and closes its socket
 *   MODE answer:<text> every prompt is answered with <text> */
static const char *mode;
static int conv(int n, const struct pam_message **m, struct pam_response **r, void *d){
  (void)d;
  if (strcmp(mode,"cancel")==0) return PAM_CONV_ERR;
  struct pam_response *a = calloc(n, sizeof *a);
  if (!a) return PAM_BUF_ERR;
  for (int i=0;i<n;i++) if (m[i]->msg_style==PAM_PROMPT_ECHO_OFF||m[i]->msg_style==PAM_PROMPT_ECHO_ON) a[i].resp=strdup(mode+7);
  *r=a; return PAM_SUCCESS;
}
int main(int c,char**v){
  mode=v[4]; struct pam_conv pc={conv,NULL}; pam_handle_t*h;
  int rc=pam_start_confdir(v[2],v[3],&pc,v[1],&h); if(rc){printf("start %d\n",rc);return 2;}
  pam_set_item(h, PAM_FAIL_DELAY, NULL);
  rc=pam_authenticate(h,0);
  printf("pam_authenticate=%d (%s)\n",rc,pam_strerror(h,rc));
  pam_end(h,rc); return 0;
}
