#ifndef CTIZENXML_H
#define CTIZENXML_H
#include <stddef.h>

/* Canonicalisation modes, matching libxml2's xmlC14NMode. */
#define TETHER_C14N_1_0        0
#define TETHER_C14N_EXCLUSIVE  1
#define TETHER_C14N_1_1        2

/* Canonicalise an entire XML document. Returns a malloc'd buffer the caller frees with
   tether_xml_free, sets *out_len; returns NULL on error. */
char *tether_c14n_doc(const char *xml, int xml_len, int mode, int *out_len);

/* Canonicalise the subtree rooted at the first element matching the XPath `xpath`,
   with inherited namespaces applied per the C14N spec. Same ownership contract as above. */
char *tether_c14n_subtree(const char *xml, int xml_len, const char *xpath, int mode, int *out_len);

void tether_xml_free(char *p);

#endif
