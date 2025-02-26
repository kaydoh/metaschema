<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:math="http://www.w3.org/2005/xpath-functions/math"
    xmlns:m="http://csrc.nist.gov/ns/oscal/metaschema/1.0"
    xmlns:XSLT="http://csrc.nist.gov/ns/oscal/metaschema/xslt-alias"
    
    xpath-default-namespace="http://csrc.nist.gov/ns/oscal/metaschema/1.0"
    exclude-result-prefixes="xs math"
    version="3.0"
    xmlns:sch="http://purl.oclc.org/dsdl/schematron"
    xmlns="http://purl.oclc.org/dsdl/schematron">
    
<!-- Purpose: Produce an Schematron representing constraints declared in a metaschema -->
<!-- Input:   A (composed) metaschema -->
<!-- Output:  A Schematron, enforcing constraints defined in the metaschema as applied to an OSCAL document -->
<!-- Dependency: Calls a function in imported XSLT `metatron-datatype-functions.xsl` to produce datatype functions on the fly -->
<!-- Maintenance note: when Saxon10 is available in tooling, try cache=yes on function declarations. -->
<!-- nb Validation against both schema and Schematron for the Metaschema format is assumed. -->
    <xsl:namespace-alias stylesheet-prefix="XSLT" result-prefix="xsl"/>
    
    <xsl:import href="../metapath/parse-metapath.xsl"/>
    
    <xsl:import href="metatron-datatype-functions.xsl"/>
    
    <xsl:output indent="yes"/>

    <xsl:strip-space elements="METASCHEMA define-assembly define-field define-flag model choice allowed-values remarks"/>
    
    <!-- set to anything but 'no' or 'false' or 'false()' to produce warnings:
         * unrecognized values in cases where allowed-values.@allow-other='yes'
    -->
    
    <xsl:param name="produce-warnings" as="xs:string">no</xsl:param>
    
<!-- Set to 'yes', produces comments for diagnosis    -->
    <xsl:param name="noisy" as="xs:string">yes</xsl:param>
    
    
    <xsl:variable name="target-namespace" select="string(/METASCHEMA/namespace)"/>
    
    <xsl:variable name="declaration-prefix" select="string(/METASCHEMA/short-name)"/>
    
    <xsl:key name="global-assembly-by-name" match="/METASCHEMA/define-assembly" use="@name"/>
    <xsl:key name="global-field-by-name"    match="/METASCHEMA/define-field"    use="@name"/>
    <xsl:key name="global-flag-by-name"     match="/METASCHEMA/define-flag"     use="@name"/>
    
    <xsl:variable name="metaschema" select="/"/>
    
    <!-- Produces intermediate results, w/o namespace alignment -->
    <!-- entry template -->
    
    <xsl:param name="debug" select="'no'"/>
    
    <!--MAIN ACTION HERE -->
    
    <xsl:template match="/" name="build-schema">
        <schema queryBinding="xslt2">
            
            <ns prefix="m" uri="http://csrc.nist.gov/ns/oscal/metaschema/1.0"/>
            <ns prefix="{ $declaration-prefix }" uri="{ $target-namespace }"/>
            <let name="silence-warnings" value="{ $produce-warnings = ('no','false','false()') }()"/>
            
            <!--<pattern>
                <rule context="/*">
                    <report test="true()" role="warning">Here be <name/></report>
                </rule>
            </pattern>-->
            
            <xsl:for-each-group select="//index | //is-unique" group-by="true()">
                <xsl:comment> INDEX DEFINITIONS AS KEY DECLARATIONS </xsl:comment>
                <xsl:apply-templates select="current-group()" mode="make-key"/>
            </xsl:for-each-group>
            
            <!--<xsl:apply-templates select="//constraint"/>-->
            <xsl:comment> RULES </xsl:comment>
            <xsl:variable name="rules" as="element()*">
              <xsl:apply-templates select="//constraint//(* except require)">
<!-- Sort into descending order by constraint definition depth
                    so deeper rules go firs-->
                  <!--<xsl:sort select="count(@target[not(.=('.','value()'))] | ancestor::require | ancestor::define-assembly | ancestor::define-flag | ancestor::define-field)" order="descending"/>-->
              </xsl:apply-templates>
            </xsl:variable>
            
            
            <!--<debug> <xsl:copy-of select="$rules"/> </debug>-->
            <pattern>
                <xsl:for-each-group select="$rules" group-by="@context">
                    <rule context="{current-grouping-key()}">
                        <xsl:sequence select="current-group()/(*|comment())"/>
                    </rule>
                </xsl:for-each-group>
            </pattern>
            
            <xsl:for-each-group select="$type-definitions[@name=$metaschema//constraint//matches/@datatype]" group-by="true()">
                <xsl:comment> LEXICAL / DATATYPE VALIDATION FUNCTIONS </xsl:comment>

                <xsl:call-template name="m:produce-validation-function"/>
                <xsl:apply-templates select="current-group()" mode="m:make-template"/>
            </xsl:for-each-group>
            
        </schema>
    </xsl:template>
    
    <xsl:variable name="types-library" select="document('oscal-datatypes.xsd')/*"/>
    
    <xsl:template match="text()"/>
    
    <!-- not actually hitting this template ... -->
    <xsl:template match="constraint">
        <xsl:apply-templates/>
    </xsl:template>
    
    <xsl:template match="matches | allowed-values | index-has-key | is-unique | expect">
        <xsl:variable name="context">
            <xsl:apply-templates select=".." mode="rule-context"/>
            <!--<xsl:for-each select="@target[not(.=('.','value()'))]">
                <xsl:text>/</xsl:text>
                <xsl:sequence select="m:target-branch(string(.),$declaration-prefix)"/>
            </xsl:for-each>-->
        </xsl:variable>
        <rule context="{ $context }">
            <xsl:apply-templates mode="assertion" select="."/>
        </rule>
    </xsl:template>
    
<!-- When a @target is designated, the context is derived from the target,
     while the assertion picks up an extra exception clause -->
    <xsl:template priority="2" match="*[matches(@target,'\S') and not(@target = ('.','value()'))]">
        <!-- Context is the last step of the target, stripped of predicates -->
        <xsl:variable name="context" select="m:prefixed-path-no-filters(string(@target),$declaration-prefix) => replace('.*/','')"/>
        <rule context="{ $context }">
            <xsl:apply-templates mode="assertion" select="."/>
        </rule>
    </xsl:template>
    
        
<!-- The has-cardinality rule handles the target differently, within the assertion,
        as it has no bearing on the match. -->
    <xsl:template priority="3" match="has-cardinality">
        <xsl:variable name="context">
            <xsl:apply-templates select=".." mode="rule-context"/>
        </xsl:variable>
        <rule context="{ $context }">
            <xsl:apply-templates mode="assertion" select="."/>
        </rule>
    </xsl:template>
    
    <!-- &&& &&& &&& &&& &&& &&& &&& &&& &&& &&& &&& &&& &&& &&& &&& &&& &&& -->
    <xsl:template match="has-cardinality/@min-occurs" mode="assertion">
        <xsl:variable name="target" select="parent::has-cardinality/@target ! m:prefixed-path(.,$declaration-prefix)"/>
        <xsl:variable name="condition" select="m:wrapper-condition(parent::has-cardinality)"/>
        <xsl:variable name="exception-clause">
            <xsl:if test="exists($condition)" expand-text="true">not({ $condition }) or</xsl:if>
        </xsl:variable>
        <assert test="{ $exception-clause } count({ $target }) le { (. cast as xs:integer) } )">
            <xsl:call-template name="id-assertion"/>
            <xsl:value-of select="m:condition(parent::has-cardinality) ! ('Where ' || . || ', ')"/><name/> is expected to have at most <xsl:value-of select="m:conditional-plural(. cast as xs:integer ,'occurrence')"/> of <xsl:value-of
                select="$target"/>
            <xsl:call-template name="label-assertion"/>
        </assert>
    </xsl:template>
    
    <xsl:template match="has-cardinality/@max-occurs" mode="assertion">
        <xsl:variable name="target" select="parent::has-cardinality/@target ! m:prefixed-path(.,$declaration-prefix)"/>
        <xsl:variable name="condition" select="m:wrapper-condition(parent::has-cardinality)"/>
        <xsl:variable name="exception-clause">
            <xsl:if test="exists($condition)" expand-text="true">not({ $condition }) or</xsl:if>
        </xsl:variable>
        <assert test="{ $exception-clause } count({ $target }) ge { (. cast as xs:integer) } )">
            <xsl:call-template name="id-assertion"/>
            <xsl:value-of select="$condition ! ('Where ' || . || ', ')"/><name/> is expected to have at least <xsl:value-of select="m:conditional-plural(. cast as xs:integer,'occurrence')"/> of <xsl:value-of select="$target"/>
            <xsl:call-template name="label-assertion"/>
        </assert>
    </xsl:template>
    
    <xsl:template priority="3" match="has-cardinality[@min-occurs = @max-occurs]" mode="assertion">
        <xsl:variable name="target" select="@target ! m:prefixed-path(.,$declaration-prefix)"/>
        <xsl:variable name="condition" select="m:wrapper-condition(.)"/>
        <xsl:variable name="exception-clause">
            <xsl:if test="exists($condition)" expand-text="true">not({ $condition }) or</xsl:if>
        </xsl:variable>
        <xsl:variable name="test" expand-text="true">count({$target}) eq { xs:integer(@min-occurs) }</xsl:variable>
        <xsl:apply-templates select="." mode="echo.if"/>
        <assert test="{ $exception-clause } { $test }">
            <xsl:call-template name="id-assertion"/>
            <xsl:value-of select="$condition ! ('Where ' || . || ', ')"/><name/> is expected to have exactly <xsl:value-of select="m:conditional-plural(@min-occurs cast as xs:integer,'occurrence')"/> of <xsl:value-of select="$target"/>
            <xsl:call-template name="label-assertion"/>
        </assert>
    </xsl:template>
    
    <xsl:template priority="2" match="has-cardinality" mode="assertion">
        <xsl:apply-templates select="." mode="echo.if"/>
        <xsl:apply-templates mode="#current" select="@min-occurs, @max-occurs"/>
    </xsl:template>
    
    <xsl:template match="index-has-key[matches(@target,'\S') and not(@target =('.','value()'))]" mode="assertion">
        <xsl:variable name="parent-context">
            <xsl:apply-templates mode="rule-context" select="ancestor::constraint"/>
        </xsl:variable>
        <xsl:variable name="exception">
            <xsl:if test="exists(m:condition(.))" expand-text="true">not({ m:condition(.) }) or </xsl:if>
        </xsl:variable>
        <xsl:variable name="test" expand-text="true">exists(key('{@name}',$lookup,ancestor::{$parent-context}))</xsl:variable>
        <xsl:apply-templates select="." mode="echo.if"/>
        <xsl:variable name="key-value-sequence">
            <xsl:call-template name="key-value-sequence"/>
        </xsl:variable>
        <let name="lookup" value="{ $key-value-sequence }"/>
        <assert test="{ $exception }{ $test }">
            <xsl:call-template name="id-assertion"/>
            <xsl:apply-templates select="." mode="qualify-report"/><name/> is expected to correspond to an entry in the '<xsl:value-of select="@name"/>' index within the containing <xsl:value-of select="$parent-context"/>
            <xsl:call-template name="label-assertion"/>
        </assert>
    </xsl:template>
    
    <xsl:template name="key-value-sequence">
        <xsl:param name="declaration-prefix"/>
        <xsl:for-each select="key-field">
            <xsl:if test="exists(preceding-sibling::key-field)">,</xsl:if>
            <xsl:if test="count(../*) gt 1">(</xsl:if>
            <xsl:value-of select="m:prefixed-path(@target/string(.), $declaration-prefix)"/>
            <xsl:for-each select="@pattern" expand-text="true">[matches(.,'^{.}$')] ! replace(.,'^{.}$','$1')</xsl:for-each>
            <xsl:if test="count(../*) gt 1">)</xsl:if>
        </xsl:for-each>
    </xsl:template>
    
    <!-- When an index-has-key is targetted not at . (or value) it needs extra logic for scoping. -->
    <xsl:template match="index-has-key" mode="assertion">
        <xsl:variable name="exception">
            <xsl:if test="exists(m:condition(.))" expand-text="true">not({ m:condition(.) }) or </xsl:if>
        </xsl:variable>
        <xsl:variable name="test" expand-text="true">exists(key('{@name}',$lookup))</xsl:variable>
        <xsl:apply-templates select="." mode="echo.if"/>
        <xsl:variable name="key-value-sequence">
            <xsl:call-template name="key-value-sequence"/>
        </xsl:variable>
        <let name="lookup" value="{ $key-value-sequence }"/>
        <assert test="{ $exception }{ $test }">
            <xsl:call-template name="id-assertion"/>
            <xsl:apply-templates select="." mode="qualify-report"/><name/> is expected to correspond to an entry in the '<xsl:value-of select="@name"/>' index.
            <xsl:call-template name="label-assertion"/>
        </assert>
    </xsl:template>
    
    <xsl:template match="is-unique[matches(@target,'\S') and not(@target =('.','value()'))]" mode="assertion">
        <xsl:variable name="parent-context">
            <xsl:apply-templates mode="rule-context" select="ancestor::constraint"/>
        </xsl:variable>
        <xsl:variable name="exception">
            <xsl:if test="exists(m:condition(.))" expand-text="true">not({ m:condition(.) }) or </xsl:if>
        </xsl:variable>
        <xsl:variable name="test" expand-text="true">exactly-one(key('{@name}',{m:key-value(.)},ancestor::{$parent-context})))</xsl:variable>
        <xsl:apply-templates select="." mode="echo.if"/>
        <assert test="{ $exception }{ $test }">
            <xsl:call-template name="id-assertion"/>
            <xsl:apply-templates select="." mode="qualify-report"/><name/> is expected to be unique within the containing <xsl:value-of select="$parent-context"/>
            <xsl:call-template name="label-assertion"/>
        </assert>
    </xsl:template>
    
    <!-- When an index-has-key is targetted not at . (or value) it needs extra logic for scoping. -->
    <xsl:template match="is-unique" mode="assertion">
        <xsl:variable name="exception">
            <xsl:if test="exists(m:condition(.))" expand-text="true">not({ m:condition(.) }) or </xsl:if>
        </xsl:variable>
        <xsl:variable name="test" expand-text="true">count(key('{@name}',{m:key-value(.)}))=1</xsl:variable>
        <xsl:apply-templates select="." mode="echo.if"/>
        <assert test="{ $exception }{ $test }">
            <xsl:call-template name="id-assertion"/>
            <xsl:apply-templates select="." mode="qualify-report"/><name/> is expected to be unique.
            <xsl:call-template name="label-assertion"/>
        </assert>
    </xsl:template>
    
    <xsl:template match="expect" mode="assertion">
        <xsl:variable name="exception">
            <xsl:if test="exists(m:condition(.))" expand-text="true">not({ m:condition(.) }) or </xsl:if>
        </xsl:variable>
        <xsl:variable name="test" expand-text="true">exists(self::node()[{ @test }])</xsl:variable>
        <xsl:apply-templates select="." mode="echo.if"/>
        <assert test="{ $exception }{ m:prefixed-path($test,$declaration-prefix) }">
            <xsl:call-template name="id-assertion"/>
            <xsl:apply-templates select="." mode="qualify-report"/><name/> fails to pass evaluation of '<xsl:value-of select="@test"/>'
            <xsl:call-template name="label-assertion"/>
        </assert>
    </xsl:template>
    
    <xsl:template match="matches/@datatype" mode="assertion">
        <xsl:variable name="exception">
            <xsl:if test="exists(m:condition(parent::matches))" expand-text="true">not({ m:condition(parent::matches) }) or </xsl:if>
        </xsl:variable> 
        <xsl:variable name="test" expand-text="true">m:datatype-validate(., '{.}')</xsl:variable>
        <xsl:apply-templates select="." mode="echo.if"/>
        <assert test="{ $exception }{ $test }">
            <xsl:call-template name="id-assertion"/>
            <xsl:value-of select="m:condition(parent::matches) ! ('Where ' || . || ', ')"/><name/> is expected to take the form of datatype <xsl:value-of select="."/>'
            <xsl:call-template name="label-assertion"/>
        </assert>
    </xsl:template>
    
    <xsl:template match="matches/@regex" mode="assertion">
        <xsl:variable name="exception">
            <xsl:if test="exists(m:condition(parent::matches))" expand-text="true">not({ m:condition(parent::matches) }) or </xsl:if>
        </xsl:variable>
        <xsl:variable name="test" expand-text="true">matches(., '^{.}$')</xsl:variable>
        <xsl:apply-templates select="." mode="echo.if"/>
        <assert test="{ $exception }{ $test }">
            <xsl:call-template name="id-assertion"/>
            <xsl:apply-templates select=".." mode="qualify-report"/>
            
            <name/> is expected to match regular expression '^<xsl:value-of select="."/>$'
            <xsl:call-template name="label-assertion"/>
        </assert>
    </xsl:template>
    
    <xsl:template match="*" mode="qualify-report">
<!-- XXX   -->
        <!--<xsl:message expand-text="true">report qualification on { @id }?</xsl:message>-->
<!-- context - different when @target is not (.,'value()')       -->
        <xsl:text>This </xsl:text>
    </xsl:template>
    
    <xsl:template match="matches" mode="assertion">    
        <xsl:apply-templates mode="#current" select="@regex | @datatype"/>
    </xsl:template>
    
    
    <xsl:template match="allowed-values" mode="assertion">
        
        <xsl:variable name="exception">
            <xsl:variable name="this-condition" select="m:condition(.)"/>
            <xsl:if test="exists($this-condition)" expand-text="true">not({ $this-condition }) or </xsl:if>
        </xsl:variable>
        <xsl:variable name="value-sequence" select="(enum/@value ! ('''' || . || '''')) => string-join(', ')"/>
        <xsl:variable name="test" as="xs:string">
            <xsl:text expand-text="true">({ @allow-other[.='yes']/'$silence-warnings or ' }. = ( { $value-sequence } ))</xsl:text>
        </xsl:variable>
        <xsl:apply-templates select="." mode="echo.if"/>
        <assert test="{ $exception }{ $test }">
            <xsl:if test="@allow-other='yes'">
                <xsl:attribute name="role">warning</xsl:attribute>
            </xsl:if>
            <xsl:call-template name="id-assertion"/>
            <xsl:apply-templates select="." mode="qualify-report"/><name/> is expected to be (one of) <xsl:value-of select="$value-sequence"/>, not '<value-of select="."/>'
            <xsl:call-template name="label-assertion"/>
        </assert>
    </xsl:template>
    
    <xsl:variable name="echo.source" select="$noisy='yes'"/>
    
    <!-- fallback template for development: should not be visited -->
    <xsl:template match="*" mode="echo.if">
        <xsl:if test="$echo.source">
            <xsl:text>&#xA;&#xA;</xsl:text>
            <xsl:comment>
                <xsl:value-of select="serialize(.,$serializer-settings)"/>
            </xsl:comment>
        </xsl:if>
    </xsl:template>
    
    <!--<xsl:template match="allowed-values" mode="echo.if">
        <xsl:if test="$echo.source">
            <xsl:text expand-text="true">&#xA;      { ancestor::*[exists(ancestor-or-self::constraint)] ! '  ' } </xsl:text>
            <xsl:comment expand-text="true">allowed-values on { m:target-match(.) }: { string-join(enum/@value,', ' ) }</xsl:comment>
        </xsl:if>
    </xsl:template>
    
    <xsl:template match="expect" mode="echo.if">
        <xsl:if test="$echo.source">
            <xsl:text expand-text="true">&#xA;      { ancestor::*[exists(ancestor-or-self::constraint)] ! '  ' } </xsl:text>
            <xsl:comment expand-text="true">expect on { m:target-match(.) }: { @test }</xsl:comment>
        </xsl:if>
    </xsl:template>
    
    <xsl:template match="matches/@regex" mode="echo.if">
        <xsl:if test="$echo.source">
            <xsl:text expand-text="true">&#xA;      { ancestor::*[exists(ancestor-or-self::constraint)] ! '  ' } </xsl:text>
            <xsl:comment expand-text="true">{ m:target-match(parent::matches) } should match regex '{ . }'</xsl:comment>
        </xsl:if>
    </xsl:template>
    
    <xsl:template match="matches/@datatype" mode="echo.if">
        <xsl:if test="$echo.source">
            <xsl:text expand-text="true">&#xA;      { ancestor::*[exists(ancestor-or-self::constraint)] ! '  ' } </xsl:text>
            <xsl:comment expand-text="true">{ m:target-match(parent::matches) } should take the form of datatype '{ . }'</xsl:comment>
        </xsl:if>
    </xsl:template>
    
    <xsl:template match="has-cardinality" mode="echo.if">
        <xsl:if test="$echo.source">
            <xsl:text expand-text="true">&#xA;      { ancestor::*[exists(ancestor-or-self::constraint)] ! '  ' } </xsl:text>
            <xsl:comment expand-text="true">{ m:target-match(.) } has cardinality: { @min-occurs ! ( ' at least ' || (.,'0')[1]) } { @max-occurs ! ( ' at most ' || (.,'unbounded')[1]) }</xsl:comment>
        </xsl:if>
    </xsl:template>
    
    <xsl:template match="index-has-key" mode="echo.if">
        <xsl:if test="$echo.source">
            <xsl:text expand-text="true">&#xA;     { ancestor::*[exists(ancestor-or-self::constraint)] ! '  ' } </xsl:text>
            <xsl:comment expand-text="true">
                <xsl:text>{ m:target-match(.) } must correspond to an entry in the '{@name}' index</xsl:text>
                <xsl:if test="matches(@target,'\S') and not(@target=('.','value()'))">
                    <xsl:text> within the context of its ancestor</xsl:text>
                    <xsl:apply-templates select="ancestor::constraint" mode="rule-context"/>
                </xsl:if>
            </xsl:comment>
        </xsl:if>
    </xsl:template>
    
    <xsl:template match="is-unique" mode="echo.if">
        <xsl:if test="$echo.source">
            <xsl:text expand-text="true">&#xA;     { ancestor::*[exists(ancestor-or-self::constraint)] ! '  ' } </xsl:text>
            <xsl:comment expand-text="true">
                <xsl:text>{ m:target-match(.) } is unique</xsl:text>
                <xsl:if test="matches(@target,'\S') and not(@target=('.','value()'))">
                    <xsl:text> within the context of its ancestor</xsl:text>
                    <xsl:apply-templates select="ancestor::constraint" mode="rule-context"/>
                </xsl:if>
            </xsl:comment>
        </xsl:if>
    </xsl:template>-->
    
    <xsl:variable name="serializer-settings" as="element()">
        <output:serialization-parameters
            xmlns="http://csrc.nist.gov/ns/oscal/metaschema/1.0"
            xmlns:output="http://www.w3.org/2010/xslt-xquery-serialization">
            <output:method value="xml"/>
            <output:version value="1.0"/>
            <output:indent value="no"/>
        </output:serialization-parameters>
    </xsl:variable>   

    <xsl:template match="flag[@ref]" mode="rule-context" as="xs:string">
        <xsl:value-of>
            <xsl:value-of select="ancestor::*/m:effective-name(.) ! m:prefixed(.)" separator="/"/>
            <xsl:text>/</xsl:text>
            <xsl:apply-templates mode="#current" select="key('global-flag-by-name',@ref)"/>
        </xsl:value-of>
    </xsl:template>
    
    <xsl:template match="assembly[@ref]" mode="rule-context" as="xs:string">
        <xsl:value-of>
            <xsl:value-of select="ancestor::*/m:effective-name(.) ! m:prefixed(.)" separator="/"/>
            <xsl:text>/</xsl:text>
            <xsl:apply-templates mode="#current" select="key('global-assembly-by-name', @ref)"/>
        </xsl:value-of>
    </xsl:template>
    
    <xsl:template match="field[@ref]" mode="rule-context" as="xs:string">
        <xsl:value-of>
            <xsl:value-of select="ancestor::*/m:effective-name(.) ! m:prefixed(.)" separator="/"/>
            <xsl:text>/</xsl:text>
            <xsl:apply-templates mode="#current" select="key('global-field-by-name', @ref)"/>
        </xsl:value-of>
    </xsl:template>
    
    <xsl:template match="define-assembly | define-field" mode="rule-context">
        <!--<xsl:for-each select="parent::model/parent::define-assembly">
            <xsl:value-of select="m:effective-name(.) / m:prefixed(.)"/>
            <xsl:text>/</xsl:text>
        </xsl:for-each>-->
        <xsl:value-of select="m:effective-name(.) / m:prefixed(.)"/>
    </xsl:template>
    
    <xsl:template priority="2" match="define-flag" mode="rule-context">
        <!--<xsl:for-each select="ancestor::define-assembly | ancestor::define-field">
            <xsl:value-of select="m:effective-name(.) / m:prefixed(.)"/>
            <xsl:text>/</xsl:text>
        </xsl:for-each>-->
        <xsl:value-of select="'@' || (use-name, @name)[1]"/>
    </xsl:template>
    
    <xsl:template match="*" mode="rule-context">
       <xsl:apply-templates select="ancestor-or-self::constraint/parent::*" mode="#current"/>
    </xsl:template>
    
    <xsl:function name="m:rule-context" as="xs:string">
        <xsl:param name="whose"/>
        <!-- Insulate XPath here -->
        <xsl:apply-templates select="$whose" mode="rule-context"/>
    </xsl:function>
    
    <xsl:function name="m:effective-name">
        <xsl:param name="whose" as="node()" required="yes"/>
        <xsl:value-of select="$whose/(root-name, use-name, @name)[1]"/>
    </xsl:function>
    
    <xsl:function name="m:prefixed" as="xs:string">
        <xsl:param name="whose"/>
        <!-- Insulate XPath here -->
        <xsl:text expand-text="true">{ $declaration-prefix }:{ $whose/string(.) }</xsl:text>
    </xsl:function>
    
    <!-- produces an "exception clause" based on targeting.
     For example, target group[@id-'ac']/control[@id='ac-2']/part[@name='statement']
    yields exception clause (with prefix 'o')
      not(self::o:part[@name='statement]/ancestor::o:control[@id='ac-2']/ancestor::o:group/@id='ac')
    -->
    <!--<xsl:function name="m:target-exception" as="xs:string?">
        <xsl:param name="whose" as="element()"/>
        <!-\- Insulate XPath here -\->
        <!-\- no-namespace paths have to be expanded to ns? -\->
        <xsl:variable name="target-path" as="xs:string">
            <xsl:apply-templates mode="okay-xpath" select="($whose/@target,'.')[1] => m:prefixed-path($declaration-prefix)"/>
        </xsl:variable>
        <xsl:sequence select="$target-path[not(.=('.','value()'))]"/>
    </xsl:function>-->
    
    <xsl:function name="m:target-match" as="xs:string?">
        <xsl:param name="whose" as="element()"/>
        <!-- Insulate XPath here -->
        <!-- no-namespace paths have to be expanded to ns? -->
        <xsl:variable name="target-path" as="xs:string">
            <xsl:apply-templates mode="okay-xpath" select="($whose/@target,'.')[1] => m:prefixed-path($declaration-prefix)"/>
        </xsl:variable>
        
        <!--JX-->
        <xsl:sequence select="$target-path[not(.=('.','value()'))]"/>
    </xsl:function>
    
    <xsl:template mode="okay-xpath" match=".">
        <xsl:sequence select="."/>
    </xsl:template>
    
    <xsl:template mode="okay-xpath" priority="100" match=".[starts-with(.,'/')]">
        <xsl:text> ( (: ... not liking absolute path </xsl:text>
        <xsl:sequence select="."/>
        <xsl:text> ... :) ) </xsl:text>
    </xsl:template>
    
    <!-- regex matches axis specifiers we want to exclude -->
    <xsl:variable name="backward-axes" as="xs:string">(parent|ancestor|ancestor-or-self|preceding-sibling|preceding)::</xsl:variable>
    
    <xsl:template mode="okay-xpath" priority="101" match=".[matches(.,$backward-axes)]">
        <xsl:text>(: not liking the reverse axis </xsl:text>
        <xsl:sequence select="."/>
        <xsl:text> :)</xsl:text>
    </xsl:template>
    
    <!-- produces a sequence of conditional tests from @when ancestry
    XXX extend this to include
      - @target ancestry and predicates
      - ancestry of locally declared constraints
    
    -->
    
    <xsl:function name="m:condition" as="xs:string?">
        <!-- Insulate XPath here -->
        <xsl:param name="whose" as="element()"/>
        <xsl:variable name="whose-context" as="xs:string?">
            <xsl:if test="matches($whose/@target,'\S') and not($whose/@target = ('.','value()'))">
                <xsl:apply-templates mode="rule-context" select="$whose/ancestor::require/ancestor::constraint"/>
            </xsl:if>
        </xsl:variable>
        
        <!-- These two are independent - $when-conditions captures require/@when
                                         $ancestry-exception expresses ancestry given in @target -->
        <!-- JX on @when -->
        
        <xsl:variable name="when-conditions" select="$whose/ancestor-or-self::*/@when ! ( $whose-context ! ('ancestor::' || . || '/') || . )"/>
        <xsl:variable name="ancestor-names" select="$whose/(ancestor::define-flag | ancestor::define-field | ancestor::define-assembly) ! m:effective-name(.)" />
        
        <!-- stitching together a match pattern from ancestors + a given @target, with steps '/.' removed -->
        <xsl:variable name="path-from-global" select="string-join(($ancestor-names,$whose/@target),'/') => replace('/\.','')"/>
        <!--JX-->
        
        <xsl:variable name="ancestry-condition" select="m:rewrite-match-as-test($path-from-global,$declaration-prefix)"/>
        
        <xsl:if test="exists(($when-conditions, $ancestry-condition))">
            <xsl:value-of select="string-join(($when-conditions, $ancestry-condition),' and ')"/>
        </xsl:if>
    </xsl:function>
    
    <!-- similar to m:condition, except relative to an aggregation not a single node -->
    <xsl:function name="m:wrapper-condition" as="xs:string?">
        <!-- Insulate XPath here -->
        <xsl:param name="whose" as="element()"/>
        <xsl:variable name="predicates" select="$whose/ancestor-or-self::require/@when"/>
        
        <!-- JX  -->
        <xsl:if test="exists($predicates)">
            <xsl:value-of select="string-join($predicates,' and ')"/>
        </xsl:if>
    </xsl:function>
    
    <xsl:function name="m:conditional-plural" as="xs:string?">
        <xsl:param name="count" as="xs:integer"/>
        <xsl:param name="noun" as="xs:string"/>
        <xsl:text expand-text="true">{ if ($count eq 1) then ('one ' || $noun) else ($count || ' ' || $noun || 's' ) }</xsl:text>
    </xsl:function>
    
    <xsl:template name="label-assertion">
        <xsl:for-each select="@id">
            <xsl:text expand-text="true">[[See {local-name()}#{.}]]</xsl:text>
        </xsl:for-each>
    </xsl:template>
    
    <xsl:template name="id-assertion">
        <xsl:where-populated>
            <xsl:attribute name="id" select="@id"/>
        </xsl:where-populated>
    </xsl:template>
    
    <xsl:template match="m:index | m:is-unique" mode="make-key">
        <xsl:variable name="context">
            <xsl:apply-templates select=".." mode="rule-context"/>
            <xsl:for-each select="@target[not(.=('.','value()'))]">
                <xsl:text>/</xsl:text>
                <xsl:sequence select="m:target-match(..) => replace('^(\./)+','')"/>
            </xsl:for-each>
        </xsl:variable>
        <!-- JX -->
        <XSLT:key name="{@name}" match="{$context}" use="{m:key-value(.)}">
            <xsl:if test="count(m:key-field) gt 1">
                <xsl:attribute name="composite">yes</xsl:attribute>
            </xsl:if>
        </XSLT:key>
    </xsl:template>
    
    <xsl:function name="m:key-value" as="xs:string">
        <xsl:param name="whose" as="element()"/>
        <!-- delimit values with '|' emitting 'string()' for any key-field with no @target or @target=('.','value()') -->
        <!-- JX -->
        <xsl:value-of separator=",">
            <xsl:sequence select="$whose/m:key-field/@target/m:prefixed-path((.[not(.=('.','value()'))],'string(.)')[1],$declaration-prefix)"/>
        </xsl:value-of>
    </xsl:function>
    
</xsl:stylesheet>