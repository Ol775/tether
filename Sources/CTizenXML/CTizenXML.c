#include "CTizenXML.h"
#include <libxml2/libxml/parser.h>
#include <libxml2/libxml/tree.h>
#include <libxml2/libxml/c14n.h>
#include <libxml2/libxml/xmlIO.h>
#include <libxml2/libxml/xpath.h>
#include <libxml2/libxml/xpathInternals.h>
#include <stdlib.h>
#include <string.h>

static char *dup_bytes(const char *src, int n, int *out_len) {
    char *copy = (char *)malloc((size_t)n + 1);
    if (!copy) return NULL;
    memcpy(copy, src, (size_t)n);
    copy[n] = '\0';
    *out_len = n;
    return copy;
}

char *tether_c14n_doc(const char *xml, int xml_len, int mode, int *out_len) {
    xmlDocPtr doc = xmlReadMemory(xml, xml_len, "in.xml", NULL, 0);
    if (!doc) return NULL;
    xmlChar *out = NULL;
    int n = xmlC14NDocDumpMemory(doc, NULL, mode, NULL, 0, &out);
    xmlFreeDoc(doc);
    if (n < 0 || !out) { if (out) xmlFree(out); return NULL; }
    char *copy = dup_bytes((const char *)out, n, out_len);
    xmlFree(out);
    return copy;
}

/* True when `anc` is an ancestor-or-self of `n` (element chain). */
static int is_ancestor_or_self(xmlNodePtr anc, xmlNodePtr n) {
    for (xmlNodePtr p = n; p; p = p->parent) if (p == anc) return 1;
    return 0;
}

/* xmlC14NExecute visibility callback. For element/text/comment/PI nodes `node` is the node;
   for attribute and namespace nodes `parent` is the owning element. A node is in the set when
   the target subtree root is an ancestor-or-self of the relevant element. */
static int is_visible(void *user_data, xmlNodePtr node, xmlNodePtr parent) {
    xmlNodePtr target = (xmlNodePtr)user_data;
    xmlNodePtr ref = node;
    if (node && (node->type == XML_ATTRIBUTE_NODE || node->type == XML_NAMESPACE_DECL)) ref = parent;
    return is_ancestor_or_self(target, ref) ? 1 : 0;
}

char *tether_c14n_subtree(const char *xml, int xml_len, const char *xpath, int mode, int *out_len) {
    xmlDocPtr doc = xmlReadMemory(xml, xml_len, "in.xml", NULL, 0);
    if (!doc) return NULL;

    /* Resolve the subtree root via the caller's XPath (first match wins). */
    xmlXPathContextPtr xp = xmlXPathNewContext(doc);
    if (!xp) { xmlFreeDoc(doc); return NULL; }
    xmlXPathObjectPtr res = xmlXPathEvalExpression((const xmlChar *)xpath, xp);
    if (!res || !res->nodesetval || res->nodesetval->nodeNr < 1) {
        if (res) xmlXPathFreeObject(res);
        xmlXPathFreeContext(xp); xmlFreeDoc(doc); return NULL;
    }
    xmlNodePtr target = res->nodesetval->nodeTab[0];

    xmlOutputBufferPtr buf = xmlAllocOutputBuffer(NULL);
    if (!buf) { xmlXPathFreeObject(res); xmlXPathFreeContext(xp); xmlFreeDoc(doc); return NULL; }
    int n = xmlC14NExecute(doc, is_visible, target, mode, NULL, 0, buf);
    char *copy = NULL;
    if (n >= 0) {
        xmlOutputBufferFlush(buf);
        const xmlChar *content = xmlOutputBufferGetContent(buf);
        size_t size = xmlOutputBufferGetSize(buf);
        if (content) copy = dup_bytes((const char *)content, (int)size, out_len);
    }
    xmlOutputBufferClose(buf);
    xmlXPathFreeObject(res);
    xmlXPathFreeContext(xp);
    xmlFreeDoc(doc);
    return copy;
}

void tether_xml_free(char *p) { free(p); }
