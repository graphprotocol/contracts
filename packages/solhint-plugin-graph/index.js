function hasLeadingUnderscore(text) {
  return text && text[0] === '_'
}

function match(text, regex) {
  return text.replace(regex, '').length === 0
}

function isMixedCase(text) {
  return match(text, /[_]*[a-z$]+[a-zA-Z0-9$]*[_]?/)
}

function isUpperSnakeCase(text) {
  return match(text, /_{0,2}[A-Z0-9$]+[_A-Z0-9$]*/)
}

class Base {
  constructor(reporter, config, source, fileName) {
    this.ignoreDeprecated = true;
    this.deprecatedPrefix = '__DEPRECATED_';
    this.underscorePrefix = '__';
    this.reporter = reporter;
    this.ignored = this.constructor.global;
    this.ruleId = this.constructor.ruleId;
    if (this.ruleId === undefined) {
      throw Error('missing ruleId static property');
    }
  }

  error(node, message, fix) {
    if (!this.ignored) {
      this.reporter.error(node, this.ruleId, message, fix);
    }
  }
}

module.exports = [
  class extends Base {
    static ruleId = 'leading-underscore';

    ContractDefinition(node) {
      if (node.kind === 'library') {
        this.inLibrary = true
      }
    }

    'ContractDefinition:exit'() {
      this.inLibrary = false
    }

    StateVariableDeclaration() {
      this.inStateVariableDeclaration = true
    }

    'StateVariableDeclaration:exit'() {
      this.inStateVariableDeclaration = false
    }

    VariableDeclaration(node) {
      if (!this.inLibrary) {
        if (!this.inStateVariableDeclaration) {
          this.validateName(node, false, 'variable')
          return
        }

        this.validateName(node, 'variable')
      }

    }

    FunctionDefinition(node) {
      if (!this.inLibrary) {
        if (!node.name) {
          return
        }
        for (const parameter of node.parameters) {
          parameter.visibility = node.visibility
        }

        this.validateName(node, 'function')

      }
    }

    validateName(node, type) {
      if (this.ignoreDeprecated && node.name.startsWith(this.deprecatedPrefix)) {
        return
      }

      const isPrivate = node.visibility === 'private'
      const isInternal = node.visibility === 'internal' || node.visibility === 'default'
      const isConstant = node.isDeclaredConst
      const isImmutable = node.isImmutable
      const shouldHaveLeadingUnderscore = (isPrivate || isInternal) && !(isConstant || isImmutable)

      if (node.name === null) {
        return
      }

      if (hasLeadingUnderscore(node.name) !== shouldHaveLeadingUnderscore) {
        this._error(node, node.name, shouldHaveLeadingUnderscore, type)
      }
    }

    fixStatement(node, shouldHaveLeadingUnderscore, type) {
      let range
  
      if (type === 'function') {
        range = node.range
        range[0] += 8
      } else if (type === 'parameter') {
        range = node.identifier.range
      } else {
        range = node.identifier.range
        range[0] -= 1
      }
  
      return (fixer) =>
        shouldHaveLeadingUnderscore
          ? fixer.insertTextBeforeRange(range, ' _')
          : fixer.removeRange([range[0] + 1, range[0] + 1])
    }

    _error(node, name, shouldHaveLeadingUnderscore, type) {
      this.error(
        node,
        `'${name}' ${shouldHaveLeadingUnderscore ? 'should' : 'should not'} start with _`, 
        // this.fixStatement(node, shouldHaveLeadingUnderscore, type)
      )
    }
  },
  class extends Base {
    static ruleId = 'func-name-mixedcase';

    FunctionDefinition(node) {
      // Allow __DEPRECATED_ prefixed functions and __ prefixed functions
      if (node.name.startsWith(this.deprecatedPrefix) || node.name.startsWith(this.underscorePrefix)) {
        return
      }

      if (!isMixedCase(node.name) && !node.isConstructor) { 
        // Allow external functions to be in UPPER_SNAKE_CASE - for immutable state getters
        if (node.visibility === 'external' && isUpperSnakeCase(node.name)) {
          return
        }
        this.error(node, 'Function name must be in mixedCase',)
      }
    }
  },
  class extends Base {
    static ruleId = 'var-name-mixedcase';
  
    VariableDeclaration(node) {
      if (node.name.startsWith(this.deprecatedPrefix)) {
        return
      }
      if (!node.isDeclaredConst && !node.isImmutable) {
        this.validateVariablesName(node)
      }
    }
  
    validateVariablesName(node) {
      if (node.name.startsWith(this.deprecatedPrefix)) {
        return
      }
      if (!isMixedCase(node.name)) {
        this.error(node, 'Variable name must be in mixedCase')
      }
    }
  }
  
];